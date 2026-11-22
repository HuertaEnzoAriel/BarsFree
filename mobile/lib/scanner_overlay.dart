import 'package:flutter/material.dart';

/// Recuadro de enfoque con esquinas y una linea laser animada que simula
/// la lectura. Cuando [success] es true se pone verde (codigo leido).
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({
    super.key,
    this.success = false,
    this.aspect = 0.45, // alto / ancho del recuadro
    this.widthFactor = 0.8,
  });

  final bool success;
  final double aspect;
  final double widthFactor;

  /// Rectangulo del recuadro dentro de un area de [size]. Lo usan tanto el
  /// dibujo como la zona real de lectura (scanWindow), para que coincidan.
  static Rect rectFor(Size size, double aspect, double widthFactor) {
    final w = size.width * widthFactor;
    final h = (w * aspect).clamp(0.0, size.height * 0.9);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: w,
      height: h,
    );
  }

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _OverlayPainter(
            t: Curves.easeInOut.transform(_ctrl.value),
            success: widget.success,
            aspect: widget.aspect,
            widthFactor: widget.widthFactor,
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.t,
    required this.success,
    required this.aspect,
    required this.widthFactor,
  });

  final double t;
  final bool success;
  final double aspect;
  final double widthFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = ScannerOverlay.rectFor(size, aspect, widthFactor);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final color = success ? Colors.greenAccent : Colors.redAccent;

    // Oscurece todo lo que queda fuera del recuadro.
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.5));

    // Relleno verde translucido al leer.
    if (success) {
      canvas.drawRRect(
        rrect,
        Paint()..color = Colors.greenAccent.withValues(alpha: 0.18),
      );
    }

    // Esquinas.
    const len = 28.0;
    final corner = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final c in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      final (p, dx, dy) = c;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy + dy * len)
          ..lineTo(p.dx, p.dy)
          ..lineTo(p.dx + dx * len, p.dy),
        corner,
      );
    }

    // Linea laser que sube y baja (se oculta al leer).
    if (!success) {
      final y = rect.top + 8 + (rect.height - 16) * t;
      final line = Rect.fromLTRB(rect.left + 10, y - 1.5, rect.right - 10, y + 1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(2)),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.t != t || old.success != success;
}
