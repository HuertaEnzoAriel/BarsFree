import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';

import 'connection_service.dart';
import 'scanner_overlay.dart';
import 'settings_screen.dart';
import 'settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CodebarsApp());
}

class CodebarsApp extends StatefulWidget {
  const CodebarsApp({super.key});

  @override
  State<CodebarsApp> createState() => _CodebarsAppState();
}

class _CodebarsAppState extends State<CodebarsApp> with WidgetsBindingObserver {
  final service = ConnectionService();
  final settings = SettingsService();
  bool loaded = false;

  /// Un unico controlador de camara para toda la app. Si cada pantalla tuviera
  /// el suyo, al pasar de una a otra el nuevo arrancaria antes de que el viejo
  /// terminara de cerrar la camara y fallaria con controllerAlreadyInitialized.
  final camera = MobileScannerController(
    autoStart: false,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf14,
      BarcodeFormat.itf2of5,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.wait([service.load(), settings.load()]).then((_) {
      setState(() => loaded = true);
      // Arranca cuando ya hay un MobileScanner montado.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
    });
  }

  Future<void> _startCamera() async {
    try {
      await camera.start();
    } catch (_) {
      // Los errores de arranque quedan en camera.value.error y los muestra
      // el errorBuilder de cada pantalla.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!loaded) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startCamera();
      case AppLifecycleState.paused:
        camera.stop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    camera.dispose();
    service.dispose();
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codebars',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: !loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ListenableBuilder(
              listenable: service,
              builder: (_, _) => service.state == LinkState.unpaired
                  ? PairScreen(service: service, camera: camera)
                  : ScanScreen(
                      service: service,
                      settings: settings,
                      camera: camera,
                    ),
            ),
    );
  }
}

/// Pantalla 1: escanear el QR que muestra el programa de la PC.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.service, required this.camera});
  final ConnectionService service;
  final MobileScannerController camera;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  bool handled = false;
  String? error;

  void onDetect(BarcodeCapture cap) {
    if (handled) return;
    for (final b in cap.barcodes) {
      final p = Pairing.fromQr(b.rawValue ?? '');
      if (p != null) {
        handled = true;
        widget.service.pair(p);
        return;
      }
    }
    setState(() => error = 'Ese QR no es del receptor de Codebars');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emparejar con la PC')),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              // El controlador es compartido: hay que fijar siempre la ventana
              // de lectura, si no quedaria la de la pantalla de escaneo.
              builder: (_, box) => Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: widget.camera,
                    scanWindow: ScannerOverlay.rectFor(box.biggest, 1, 0.65),
                    onDetect: onDetect,
                    errorBuilder: (_, e) => _CameraError(e),
                  ),
                  const ScannerOverlay(aspect: 1, widthFactor: 0.65),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error ??
                  'En la PC ejecuta el receptor (node index.js) y apunta la '
                      'camara al QR que aparece en la consola.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla 2: escaneo continuo; cada codigo se envia a la PC.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.service,
    required this.settings,
    required this.camera,
  });
  final ConnectionService service;
  final SettingsService settings;
  final MobileScannerController camera;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  MobileScannerController get controller => widget.camera;
  String lastCode = '';
  DateTime lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool flash = false;
  bool hit = false; // true un instante despues de leer un codigo
  Timer? hitTimer;

  static const _dedup = Duration(milliseconds: 1500);
  static const _boxAspect = 0.45; // alto / ancho del recuadro de lectura
  static const _boxWidth = 0.8; // ancho del recuadro respecto a la camara

  final player = AudioPlayer();

  /// Vibra con el motor del telefono. HapticFeedback no sirve aqui: depende de
  /// la opcion "respuesta haptica" del sistema y a menudo no vibra.
  Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator() == true) {
        await Vibration.vibrate(duration: 120);
      } else {
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {}
  }

  /// Reproduce el beep desde el inicio cada vez, aunque el anterior siga sonando.
  Future<void> _beep() async {
    try {
      await player.stop();
      await player.play(AssetSource('beep.mp3'));
    } catch (_) {}
  }

  void onDetect(BarcodeCapture cap) {
    final svc = widget.service;
    if (svc.state != LinkState.connected) return;
    for (final b in cap.barcodes) {
      final code = b.rawValue;
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now();
      if (code == lastCode && now.difference(lastAt) < _dedup) return;
      lastCode = code;
      lastAt = now;
      svc.send(code, sendKey: widget.settings.sendKey);
      if (widget.settings.vibration) _vibrate();
      if (widget.settings.sound) _beep();
      setState(() => hit = true);
      hitTimer?.cancel();
      hitTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => hit = false);
      });
      return;
    }
  }

  @override
  void dispose() {
    hitTimer?.cancel();
    player.dispose();
    // La camara sigue viva para la pantalla de emparejar; solo apagamos la
    // linterna si quedo encendida.
    if (flash) controller.toggleTorch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    final connected = svc.state == LinkState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Codebars'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: Icon(flash ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              controller.toggleTorch();
              setState(() => flash = !flash);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(settings: widget.settings),
                ));
              } else if (v == 'unpair') {
                svc.unpair();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Configuracion')),
              PopupMenuItem(value: 'unpair', child: Text('Desemparejar')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: connected ? Colors.green.shade700 : Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              connected
                  ? 'Conectado a ${svc.pcName ?? 'la PC'}'
                  : 'Buscando la PC... (misma red WiFi)',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                // Solo se lee lo que esta dentro del recuadro visible.
                final window = ScannerOverlay.rectFor(
                  box.biggest,
                  _boxAspect,
                  _boxWidth,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: controller,
                      scanWindow: window,
                      onDetect: onDetect,
                      errorBuilder: (_, e) => _CameraError(e),
                    ),
                    ScannerOverlay(
                      success: hit,
                      aspect: _boxAspect,
                      widthFactor: _boxWidth,
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              svc.lastSent == null
                  ? 'Apunta la camara a un codigo de barras'
                  : 'Enviado: ${svc.lastSent}',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.error);
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          denied
              ? 'Se necesita permiso de camara. Activalo en Ajustes > Apps > Codebars.'
              : 'Error de camara: ${error.errorCode.name}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
