// Soft living-room background behind found things.
// For now: zooms into the window + sofa side of scene_home (away from Juju)
// and blurs it. When a Juju-free room image exists, point `asset` at it and
// remove the Transform.scale and ImageFiltered wrappers.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class RoomBackdrop extends StatelessWidget {
  final Widget child;
  final String asset;
  final BorderRadius radius;
  const RoomBackdrop({
    super.key,
    required this.child,
    this.asset = 'assets/places/scene_home.webp',
    this.radius = const BorderRadius.all(Radius.circular(26)),
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: radius,
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Transform.scale(
                  scale: 2.4, // zoom into the window + sofa side
                  alignment: const Alignment(-1, -0.2),
                  child: Image.asset(asset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFFF3EBDD))),
                ),
              ),
            ),
          ),
          Container(color: Colors.white.withOpacity(0.25)),
          child,
        ]),
      );
}
