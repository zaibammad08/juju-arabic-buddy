// lib/widgets/feed_juju_desert.dart
//
// Desert scene for the Feed Juju game: same sand palette and dune shapes as
// the Juju Detective panel, with Juju standing in the middle and a woven
// basket at her feet.
//
//   hungry   – slow breathing bob + a little tummy-rumble wobble every 4 s
//   eating   – the food sticker drops into the basket, then Juju hops twice
//   notQuite – Juju tilts her head every few seconds; with FoodSpot.sand the
//              snack sits on the sand next to her, not in the basket
//
// The screen owns the game state; this widget only shows it.
// Respects "reduce motion" (MediaQuery.disableAnimations).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FeedMood { hungry, eating, notQuite }

/// Where the food goes: into the basket (eaten) or on the sand (not eaten).
enum FoodSpot { basket, sand }

class DesertColors {
  static const sky = Color(0xFFFEF4E2);
  static const backDune = Color(0xFFF4DCAA);
  static const frontDune = Color(0xFFEBC689);
  static const ripple = Color(0xFFD6AA66);
  static const sun = Color(0xFFFCD46A);
  static const shadow = Color(0x26A0763F);
  static const palmTrunk = Color(0xFFA9774A);
  static const palmRing = Color(0xFF8A5E37);
  static const palmLeaf = Color(0xFF6FA45A);
  static const palmLeafDark = Color(0xFF558A45);
  static const basket = Color(0xFFD9A066);
  static const basketWeave = Color(0xFFB9824A);
  static const basketRim = Color(0xFFC68A50);
  static const basketInside = Color(0xFF8E5E34);
}

/// Reusable sand backdrop. Detective can use it too so both games match.
class DesertPainter extends CustomPainter {
  const DesertPainter({this.showSun = true, this.showPalm = false});

  final bool showSun;
  final bool showPalm;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    canvas.drawRect(Offset.zero & s, Paint()..color = DesertColors.sky);

    // Sun first, so the back dune hides its lower half.
    if (showSun) {
      canvas.drawCircle(
        Offset(w * 0.80, h * 0.40),
        math.min(w, h) * 0.13,
        Paint()..color = DesertColors.sun,
      );
    }

    final back = Path()
      ..moveTo(0, h * 0.44)
      ..cubicTo(w * 0.22, h * 0.32, w * 0.42, h * 0.38, w * 0.60, h * 0.45)
      ..cubicTo(w * 0.74, h * 0.51, w * 0.88, h * 0.42, w, h * 0.40)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = DesertColors.backDune);

    if (showPalm) {
      // Sized from the panel height so the fronds never get clipped,
      // even when the desert panel is short.
      _palm(canvas, Offset(w * 0.14, h * 0.42), math.min(h / 430, w / 320));
    }

    final front = Path()
      ..moveTo(0, h * 0.64)
      ..cubicTo(w * 0.30, h * 0.57, w * 0.62, h * 0.62, w, h * 0.57)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = DesertColors.frontDune);

    final ripple = Paint()
      ..color = DesertColors.ripple.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    void line(double x0, double x1, double y) {
      canvas.drawPath(
        Path()
          ..moveTo(w * x0, h * y)
          ..quadraticBezierTo(w * (x0 + x1) / 2, h * y - 7, w * x1, h * y + 2),
        ripple,
      );
    }

    line(0.08, 0.36, 0.72);
    line(0.62, 0.92, 0.70);
    line(0.10, 0.40, 0.88);
    line(0.58, 0.90, 0.86);
  }

  void _palm(Canvas c, Offset base, double scale) {
    final top = base + Offset(10 * scale, -110 * scale);
    final trunk = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(
          base.dx - 14 * scale, base.dy - 60 * scale, top.dx, top.dy);
    c.drawPath(
      trunk,
      Paint()
        ..color = DesertColors.palmTrunk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9 * scale
        ..strokeCap = StrokeCap.round,
    );

    final ring = Paint()
      ..color = DesertColors.palmRing
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;
    for (final m in trunk.computeMetrics()) {
      for (var d = m.length * 0.15; d < m.length * 0.95; d += 12 * scale) {
        final t = m.getTangentForOffset(d);
        if (t == null) continue;
        final n = Offset(-t.vector.dy, t.vector.dx) * (4 * scale);
        c.drawLine(t.position - n, t.position + n, ring);
      }
    }

    // Fronds fan out from the top and droop towards the ground.
    const angles = [-2.75, -2.25, -1.57, -0.90, -0.40];
    for (var i = 0; i < angles.length; i++) {
      final a = angles[i];
      final droop = a < -1.57 ? -1.0 : 1.0;
      final len = (i.isEven ? 62.0 : 54.0) * scale;
      c.save();
      c.translate(top.dx, top.dy);
      c.rotate(a);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
            len * 0.5, -len * 0.22 * droop, len, len * 0.18 * droop)
        ..quadraticBezierTo(len * 0.5, len * 0.10 * droop, 0, 0)
        ..close();
      c.drawPath(
        leaf,
        Paint()
          ..color =
              i.isEven ? DesertColors.palmLeaf : DesertColors.palmLeafDark,
      );
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DesertPainter old) =>
      old.showSun != showSun || old.showPalm != showPalm;
}

/// Basket in two layers so the food can sit *inside* it:
/// back = the dark opening, front = woven body + rim.
class _BasketPainter extends CustomPainter {
  const _BasketPainter({required this.front});

  final bool front;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final rimH = h * 0.34;
    final rim = Rect.fromLTWH(0, 0, w, rimH).deflate(h * 0.03);

    if (!front) {
      c.drawOval(rim, Paint()..color = DesertColors.basketInside);
      return;
    }

    final body = Path()
      ..moveTo(0, rimH / 2)
      ..cubicTo(w * 0.02, h * 0.98, w * 0.98, h * 0.98, w, rimH / 2)
      ..arcTo(rim, 0, math.pi, false)
      ..close();
    c.drawPath(body, Paint()..color = DesertColors.basket);

    c.save();
    c.clipPath(body);
    final across = Paint()
      ..color = DesertColors.basketWeave
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.045;
    for (var i = 1; i <= 3; i++) {
      final y = rimH * 0.6 + (h - rimH * 0.6) * i / 4.0;
      c.drawPath(
        Path()
          ..moveTo(0, y - h * 0.05)
          ..quadraticBezierTo(w / 2, y + h * 0.06, w, y - h * 0.05),
        across,
      );
    }
    final down = Paint()
      ..color = DesertColors.basketWeave.withOpacity(0.6)
      ..strokeWidth = h * 0.025;
    for (var i = 1; i < 8; i++) {
      final x = w * i / 8;
      c.drawLine(
        Offset(x, rimH / 2),
        Offset(w / 2 + (x - w / 2) * 0.7, h),
        down,
      );
    }
    c.restore();

    c.drawOval(
      rim,
      Paint()
        ..color = DesertColors.basketRim
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.07,
    );
  }

  @override
  bool shouldRepaint(covariant _BasketPainter old) => old.front != front;
}

class FeedJujuDesert extends StatefulWidget {
  const FeedJujuDesert({
    super.key,
    required this.mood,
    required this.jujuBuilder,
    this.food,
    this.foodSpot = FoodSpot.basket,
    this.onJujuTap,
    this.showPalm = true,
    this.radius = 32,
  });

  /// Driven by the screen: hungry → (photo checked) → eating / notQuite.
  final FeedMood mood;

  /// Return your Juju widget for the current mood, e.g.
  /// `(mood, size) => Juju(pose: ..., size: size)`.
  final Widget Function(FeedMood mood, double size) jujuBuilder;

  /// Sticker of the food the child showed. Drops into the basket on `eating`.
  final Widget? food;

  /// basket = drops in when eating; sand = sits beside Juju (any mood but hungry).
  final FoodSpot foodSpot;

  final VoidCallback? onJujuTap;
  final bool showPalm;
  final double radius;

  @override
  State<FeedJujuDesert> createState() => _FeedJujuDesertState();
}

class _FeedJujuDesertState extends State<FeedJujuDesert>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _rumble = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _drop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _hop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _tilt = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  Timer? _rumbleTimer;
  bool _reduceMotion = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion) {
      _idle.stop();
      _rumbleTimer?.cancel();
      _rumbleTimer = null;
    } else {
      if (!_idle.isAnimating) _idle.repeat();
      _rumbleTimer ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        if (widget.mood == FeedMood.hungry) _rumble.forward(from: 0);
        if (widget.mood == FeedMood.notQuite) _tilt.forward(from: 0);
      });
    }
    if (!_started) {
      _started = true;
      _syncMood(initial: true);
    }
  }

  @override
  void didUpdateWidget(covariant FeedJujuDesert old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _syncMood();
  }

  void _syncMood({bool initial = false}) {
    switch (widget.mood) {
      case FeedMood.hungry:
        _drop.value = 0;
        _hop.value = 0;
        _tilt.value = 0;
        break;
      case FeedMood.eating:
        if (_reduceMotion || initial) {
          _drop.value = 1;
        } else {
          _drop.forward(from: 0).then((_) {
            if (mounted) _hop.forward(from: 0);
          });
        }
        break;
      case FeedMood.notQuite:
        if (!_reduceMotion) _tilt.forward(from: 0);
        break;
    }
  }

  @override
  void dispose() {
    _rumbleTimer?.cancel();
    _idle.dispose();
    _rumble.dispose();
    _drop.dispose();
    _hop.dispose();
    _tilt.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.mood) {
      case FeedMood.hungry:
        return 'Juju is waiting next to an empty basket';
      case FeedMood.eating:
        return 'Juju is eating the food';
      case FeedMood.notQuite:
        return 'Juju is not sure about this one';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

          final jujuSize = math.min(h * 0.58, w * 0.60);
          final jujuCx = w * 0.44;
          final jujuBottom = h * 0.12;

          final basketW = math.min(w * 0.34, jujuSize * 0.62);
          final basketH = basketW * 0.55;
          final basketCx = w * 0.66;
          final basketBottom = h * 0.06;
          final basketTop = h - basketBottom - basketH;

          final foodSize = basketW * 0.62;
          final foodBottomFromTop = basketTop + basketH * 0.22;

          return AnimatedBuilder(
            animation: Listenable.merge([_idle, _rumble, _drop, _hop, _tilt]),
            builder: (context, _) {
              final bob = _reduceMotion
                  ? 0.0
                  : math.sin(_idle.value * 2 * math.pi) * 3.0;
              final hop =
                  (math.sin(_hop.value * 2 * math.pi)).abs() * jujuSize * 0.10;
              final rumble = math.sin(_rumble.value * math.pi * 8) *
                  0.035 *
                  (1 - _rumble.value);
              final tilt = math.sin(_tilt.value * math.pi) * 0.14;

              final dropT = Curves.easeOutBack.transform(_drop.value);
              final inBasket = widget.food != null &&
                  widget.foodSpot == FoodSpot.basket &&
                  widget.mood == FeedMood.eating;
              final onSand = widget.food != null &&
                  widget.foodSpot == FoodSpot.sand &&
                  widget.mood != FeedMood.hungry;
              final sandCx = w * 0.15;
              final sandBottom = h * 0.07;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DesertPainter(showPalm: widget.showPalm),
                    ),
                  ),

                  // Soft shadow under Juju (shrinks when she hops).
                  Positioned(
                    left: jujuCx - jujuSize * 0.30,
                    bottom: jujuBottom - jujuSize * 0.04,
                    width: jujuSize * 0.60,
                    height: jujuSize * 0.10,
                    child: Transform.scale(
                      scale: 1 - (hop / (jujuSize * 0.10)) * 0.25,
                      child: const DecoratedBox(
                        decoration: ShapeDecoration(
                          color: DesertColors.shadow,
                          shape: OvalBorder(),
                        ),
                      ),
                    ),
                  ),

                  // Juju.
                  Positioned(
                    left: jujuCx - jujuSize / 2,
                    bottom: jujuBottom,
                    width: jujuSize,
                    height: jujuSize,
                    child: Transform.translate(
                      offset: Offset(0, -bob - hop),
                      child: Transform.rotate(
                        angle: rumble + tilt,
                        alignment: Alignment.bottomCenter,
                        child: GestureDetector(
                          onTap: widget.onJujuTap,
                          child: widget.jujuBuilder(widget.mood, jujuSize),
                        ),
                      ),
                    ),
                  ),

                  // Basket shadow.
                  Positioned(
                    left: basketCx - basketW * 0.55,
                    bottom: basketBottom - basketH * 0.10,
                    width: basketW * 1.1,
                    height: basketH * 0.30,
                    child: const DecoratedBox(
                      decoration: ShapeDecoration(
                        color: DesertColors.shadow,
                        shape: OvalBorder(),
                      ),
                    ),
                  ),

                  // Basket opening (behind the food).
                  Positioned(
                    left: basketCx - basketW / 2,
                    bottom: basketBottom,
                    width: basketW,
                    height: basketH,
                    child: const CustomPaint(
                      painter: _BasketPainter(front: false),
                    ),
                  ),

                  // Snack left on the sand (not eaten).
                  if (onSand) ...[
                    Positioned(
                      left: sandCx - foodSize * 0.45,
                      bottom: sandBottom - foodSize * 0.06,
                      width: foodSize * 0.9,
                      height: foodSize * 0.18,
                      child: const DecoratedBox(
                        decoration: ShapeDecoration(
                          color: DesertColors.shadow,
                          shape: OvalBorder(),
                        ),
                      ),
                    ),
                    Positioned(
                      left: sandCx - foodSize / 2,
                      bottom: sandBottom,
                      width: foodSize,
                      height: foodSize,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: _reduceMotion ? 1 : 0.5, end: 1),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutBack,
                        builder: (context, v, child) => Transform.scale(
                          scale: v,
                          alignment: Alignment.bottomCenter,
                          child: child,
                        ),
                        child: FittedBox(child: widget.food),
                      ),
                    ),
                  ],

                  // Food drops in from above.
                  if (inBasket)
                    Positioned(
                      left: basketCx - foodSize / 2,
                      top: foodBottomFromTop - foodSize,
                      width: foodSize,
                      height: foodSize,
                      child: Transform.translate(
                        offset: Offset(0, (1 - dropT) * -h * 0.40),
                        child: Opacity(
                          opacity: _drop.value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * dropT,
                            alignment: Alignment.bottomCenter,
                            child: FittedBox(child: widget.food),
                          ),
                        ),
                      ),
                    ),

                  // Basket body + rim (in front of the food).
                  Positioned(
                    left: basketCx - basketW / 2,
                    bottom: basketBottom,
                    width: basketW,
                    height: basketH,
                    child: const CustomPaint(
                      painter: _BasketPainter(front: true),
                    ),
                  ),
                ],
              );
            },
          );
        }),
      ),
    );
  }
}
