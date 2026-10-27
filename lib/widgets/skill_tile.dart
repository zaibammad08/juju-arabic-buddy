import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'juju.dart';

/// One of the 4 skill tiles on the My Letter hub: Listen · Speak · Read · Write.
/// Juju holds her prop (headphones / microphone / book / pencil).
/// done = green ✓, next = red NEXT label, todo = plain. Never a ✗.
class SkillTile extends StatelessWidget {
  const SkillTile({
    super.key,
    required this.label,
    required this.pose,
    required this.state,
    required this.onTap,
    this.color = AppColors.accent,
  });

  final String label;
  final JujuPose pose;
  final SkillState state;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isNext = state == SkillState.next;
    return Semantics(
      button: true,
      label: '$label${state == SkillState.done ? ', done' : isNext ? ', next' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 120, minWidth: AppTheme.minTap),
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isNext ? color : AppColors.line,
                  width: isNext ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 5), blurRadius: 0),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Juju(pose: pose, size: 64, motion: isNext ? JujuMotion.bounce : JujuMotion.none),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: AppTheme.english(size: 16, weight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            if (state == SkillState.done)
              const Positioned(
                top: -8,
                right: -6,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.good,
                  child: Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            if (isNext)
              Positioned(
                top: -10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.highlight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('NEXT',
                        style: AppTheme.english(
                            size: 13, color: Colors.white, weight: FontWeight.w800)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
