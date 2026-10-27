import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

/// Juju's pose images: assets/mascot/camel_<file>.webp (from generate_stickers.py).
enum JujuPose {
  base('base'),
  threeQuarter('3q'),
  idle('idle'),
  wave('wave'),
  talking('talking'),
  listening('listening'),
  thinking('thinking'),
  happy('happy'),
  encourage('encourage'),
  proud('proud'),
  sleepy('sleepy'),
  painting('painting'),
  camera('camera'),
  book('book'),
  card('card'),
  board1('board_1'),
  board2('board_2'),
  board3('board_3'),
  confused('confused'),
  faceIcon('face_icon'),
  badge('badge'),
  pointLeft('point_left'),
  pointRight('point_right'),
  pointDown('point_down'),
  headphones('headphones'), // Listen tile
  microphone('microphone'), // Speak tile
  pencil('pencil'), // Write tile (Read uses book)
  gradCap('grad_cap'),
  rewardStar('reward_star'),
  rewardTrophy('reward_trophy'),
  rewardMedal('reward_medal'),
  sad('sad'),
  surprised('surprised'),
  tired('tired'),
  bagNew('bag_new'),
  bagOld('bag_old'),
  bagHeavy('bag_heavy'),
  bagLight('bag_light');

  const JujuPose(this.file);
  final String file;

  String get asset => 'assets/mascot/camel_$file.webp';

  /// Favourite-colour backpack, e.g. backpack('red').
  static String backpack(String colourId) => 'assets/mascot/camel_backpack_$colourId.webp';
}

enum JujuMotion { none, bounce, wiggle, pop }

/// Juju by pose, with a gentle idle motion. Tap → onTap (e.g. Juju Corner).
/// Falls back to a 🐪 if the image isn't in assets yet.
class Juju extends StatelessWidget {
  const Juju({
    super.key,
    this.pose = JujuPose.idle,
    this.size = 160,
    this.motion = JujuMotion.bounce,
    this.onTap,
    this.assetOverride,
    this.semanticLabel = 'Juju the camel',
  });

  final JujuPose pose;
  final double size;
  final JujuMotion motion;
  final VoidCallback? onTap;
  final String? assetOverride; // e.g. JujuPose.backpack('red')
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(
      assetOverride ?? pose.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: Center(child: Text('🐪', style: TextStyle(fontSize: size * 0.6))),
      ),
    );

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduceMotion) {
      switch (motion) {
        case JujuMotion.bounce:
          img = img
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -6, duration: 1100.ms, curve: Curves.easeInOut);
        case JujuMotion.wiggle:
          img = img
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .rotate(begin: -0.015, end: 0.015, duration: 700.ms, curve: Curves.easeInOut);
        case JujuMotion.pop:
          img = img
              .animate()
              .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1),
                  duration: 450.ms, curve: Curves.elasticOut);
        case JujuMotion.none:
          break;
      }
    }

    // Smooth swap when the pose changes.
    img = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(assetOverride ?? pose.asset), child: img),
    );

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: onTap == null
          ? img
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: img),
    );
  }
}

/// White speech bubble with a small tail, for Juju's short lines.
/// Put Arabic inside with ArabicText (it handles RTL).
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.child, this.tailOnLeft = true});

  final Widget child;
  final bool tailOnLeft;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(tailOnLeft: tailOnLeft),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.tailOnLeft});
  final bool tailOnLeft;

  @override
  void paint(Canvas canvas, Size size) {
    const tail = 12.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - tail),
      const Radius.circular(24),
    );
    final x = tailOnLeft ? 34.0 : size.width - 34.0;
    final path = Path()
      ..addRRect(body)
      ..moveTo(x - 10, size.height - tail)
      ..lineTo(x + (tailOnLeft ? -6 : 6), size.height)
      ..lineTo(x + 10, size.height - tail)
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 4)), Paint()..color = AppColors.line);
    canvas.drawPath(path, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tailOnLeft != tailOnLeft;
}
