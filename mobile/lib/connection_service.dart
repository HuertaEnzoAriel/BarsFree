import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LinkState { unpaired, connecting, connected }

/// Datos de emparejamiento que muestra el QR de la PC.
class Pairing {
  Pairing(this.hosts, this.port, this.token, [this.id]);
  final List<String> hosts;
  final int port;
  final String token;
  final String? id; // identificador publico para el descubrimiento UDP

  static Pairing? fromQr(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final hosts = (m['h'] as List).cast<String>();
      final port = m['p'] as int;
      final token = m['t'] as String;
      if (hosts.isEmpty || token.isEmpty) return null;
      return Pairing(hosts, port, token, m['i'] as String?);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() =>
      {'h': hosts, 'p': port, 't': token, if (id != null) 'i': id};
}

/// Mantiene la conexion WebSocket con la PC y reconecta sola.
class ConnectionService extends ChangeNotifier {
  LinkState state = LinkState.unpaired;
  String? pcName;
  String? lastSent;
  Pairing? _pairing;
  WebSocketChannel? _channel;
  bool _disposed = false;
  int _generation = 0; // invalida bucles de reconexion viejos

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pairing');
    if (raw != null) {
      _pairing = Pairing.fromQr(raw);
      if (_pairing != null) _start();
    }
    notifyListeners();
  }

  Future<void> _save(Pairing p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pairing', jsonEncode(p.toJson()));
  }

  Future<void> pair(Pairing p) async {
    _pairing = p;
    await _save(p);
    _start();
  }

  Future<void> unpair() async {
    _generation++;
    _channel?.sink.close();
    _channel = null;
    _pairing = null;
    pcName = null;
    state = LinkState.unpaired;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pairing');
    notifyListeners();
  }

  void send(String code) {
    if (state != LinkState.connected) return;
    _channel?.sink.add(jsonEncode({'type': 'scan', 'code': code}));
    lastSent = code;
    notifyListeners();
  }

  void _start() {
    final gen = ++_generation;
    _channel?.sink.close();
    _loop(gen);
  }

  Future<void> _loop(int gen) async {
    while (!_disposed && gen == _generation && _pairing != null) {
      state = LinkState.connecting;
      notifyListeners();

      var ch = await _connectAny(_pairing!);
      if (ch == null && gen == _generation) {
        // La IP pudo cambiar: buscamos la PC en la red y reintentamos.
        final found = await _discover(_pairing!);
        if (found != null && gen == _generation) {
          _pairing = found;
          await _save(found);
          ch = await _connectAny(found);
        }
      }
      if (gen != _generation) {
        ch?.sink.close();
        return;
      }
      if (ch != null) {
        _channel = ch;
        state = LinkState.connected;
        notifyListeners();
        final done = Completer<void>();
        ch.stream.listen(
          (data) {
            try {
              final m = jsonDecode(data as String) as Map<String, dynamic>;
              if (m['type'] == 'hello') {
                pcName = m['host'] as String?;
                notifyListeners();
              }
            } catch (_) {}
          },
          onDone: () => done.complete(),
          onError: (_) {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        await done.future;
        if (gen != _generation) return;
        _channel = null;
        state = LinkState.connecting;
        notifyListeners();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<WebSocketChannel?> _connectAny(Pairing p) async {
    for (final host in p.hosts) {
      try {
        final ch = WebSocketChannel.connect(Uri(
          scheme: 'ws',
          host: host,
          port: p.port,
          queryParameters: {'token': p.token},
        ));
        await ch.ready.timeout(const Duration(seconds: 3));
        return ch;
      } catch (_) {}
    }
    return null;
  }

  /// Descubrimiento por UDP broadcast: pregunta "donde esta mi PC?" y el
  /// receptor responde con su IP actual (puerto de descubrimiento = puerto + 1).
  Future<Pairing?> _discover(Pairing p) async {
    final id = p.id;
    if (id == null) return null; // emparejado con version vieja: re-emparejar
    RawDatagramSocket? sock;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock = s;
      s.broadcastEnabled = true;
      final udpPort = p.port + 1;

      final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
      try {
        for (final ni
            in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final a in ni.addresses) {
            final o = a.address.split('.');
            if (o.length == 4) {
              targets.add(InternetAddress('${o[0]}.${o[1]}.${o[2]}.255'));
            }
          }
        }
      } catch (_) {}

      final result = Completer<Pairing?>();
      sub = s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
          if (m['type'] != 'here' || m['id'] != id) return;
          final hosts = <String>{
            d.address.address,
            ...(m['h'] as List).cast<String>(),
          }.toList();
          if (!result.isCompleted) {
            result.complete(
                Pairing(hosts, (m['p'] as int?) ?? p.port, p.token, id));
          }
        } catch (_) {}
      });

      final msg = utf8.encode(jsonEncode({'type': 'find', 'id': id}));
      for (var i = 0; i < 3 && !result.isCompleted; i++) {
        for (final t in targets) {
          try {
            s.send(msg, t, udpPort);
          } catch (_) {}
        }
        await Future.any(
            [result.future, Future<void>.delayed(const Duration(seconds: 1))]);
      }
      return result.isCompleted ? await result.future : null;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      sock?.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    super.dispose();
  }
}
