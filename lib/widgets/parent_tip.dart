import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft yellow tip box for grown-ups (English). Optional listen button.
class ParentTip extends StatelessWidget {
  const ParentTip(
      {super.key,
      required this.text,
      this.title = 'Parent tip',
      this.onListen});

  final String text;
  final String title;
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.tip,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withAlpha(110), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('💡', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.english(size: 15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(text,
                    style: AppTheme.english(size: 15, color: AppColors.muted)),
              ],
            ),
          ),
          if (onListen != null)
            IconButton(
              onPressed: onListen,
              tooltip: 'Listen',
              icon: const Icon(Icons.volume_up_rounded, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}
