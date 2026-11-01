// Shared treasure chest painter.
// Used by Unlock the Treasure (3 locks) and the Treasure Hunt reveal (1 lock).
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ChestPainter extends CustomPainter {
  final int open; // locks already open
  final int total; // number of locks
  final double lid; // 0 shut .. 1 flung open
  ChestPainter({required this.open, required this.total, this.lid = 0});

  @override
  void paint(Canvas canvas, Size s) {
    const wood = Color(0xFFC98A3E);
    const dark = Color(0xFF6B4318);
    final stroke = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final allOpen = lid > 0.02;
    // golden light from inside
    if (allOpen) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(s.width * 0.5, s.height * 0.4),
              width: s.width * 0.9,
              height: s.height * 0.5 * lid),
          Paint()
            ..color =
                const Color(0xFFFFE066).withOpacity(0.85 * lid.clamp(0.0, 1.0))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    // lid: tips back on its hinge as it opens
    canvas.save();
    canvas.translate(s.width * 0.93, s.height * 0.44);
    canvas.rotate(lid * 0.55);
    canvas.translate(-s.width * 0.93, -s.height * 0.44);
    final lidPath = Path()
      ..moveTo(s.width * 0.07, s.height * 0.44)
      ..quadraticBezierTo(s.width * 0.5, s.height * (0.05 - 0.3 * lid),
          s.width * 0.93, s.height * 0.44)
      ..close();
    canvas.drawPath(lidPath, Paint()..color = const Color(0xFFB0722F));
    canvas.drawPath(lidPath, stroke);
    canvas.restore();
    // box
    final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            s.width * 0.07, s.height * 0.42, s.width * 0.86, s.height * 0.54),
        const Radius.circular(8));
    canvas.drawRRect(box, Paint()..color = wood);
    canvas.drawRRect(box, stroke);
    // locks, spread evenly across the front
    for (var i = 0; i < total; i++) {
      final cx = s.width * ((i + 1) / (total + 1));
      final r = Rect.fromCenter(
          center: Offset(cx, s.height * 0.72),
          width: s.width * 0.13,
          height: s.height * 0.16);
      final isOpen = i < open;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = isOpen ? AppColors.good : AppColors.blue);
      final shackle = Path()
        ..moveTo(r.left + r.width * 0.2, r.top)
        ..lineTo(r.left + r.width * 0.2, r.top - r.height * 0.35)
        ..arcToPoint(
            Offset(r.right - r.width * 0.2,
                r.top - r.height * (isOpen ? 0.6 : 0.35)),
            radius: Radius.circular(r.width * 0.3))
        ..lineTo(
            r.right - r.width * 0.2, isOpen ? r.top - r.height * 0.35 : r.top);
      canvas.drawPath(
          shackle,
          Paint()
            ..color = dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5);
    }
  }

  @override
  bool shouldRepaint(covariant ChestPainter old) =>
      old.open != open || old.lid != lid || old.total != total;
}
