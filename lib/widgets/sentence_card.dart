import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'arabic_text.dart';

/// One sentence: Arabic (chosen words coloured), how to say it, English,
/// and Listen / "I said it!" buttons. Used by the story and core sentences.
class SentenceCard extends StatelessWidget {
  const SentenceCard({
    super.key,
    required this.line,
    this.onListen,
    this.onSaid,
    this.showPhonetic = true,
    this.showEnglish = true,
    this.picture,
    this.counter,
  });

  final SentenceLine line;
  final VoidCallback? onListen;
  final VoidCallback? onSaid;
  final bool showPhonetic;
  final bool showEnglish;
  final Widget? picture; // story page image
  final String? counter; // e.g. "2 / 5"

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 6), blurRadius: 0),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counter != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(counter!,
                  style: AppTheme.english(size: 14, color: AppColors.muted)),
            ),
          if (picture != null) ...[
            ClipRRect(borderRadius: BorderRadius.circular(20), child: picture),
            const SizedBox(height: 12),
          ],
          ArabicText(line.arabic, size: 34, highlightWords: line.highlight),
          if (showPhonetic && line.phonetic.isNotEmpty)
            Text(line.phonetic,
                textAlign: TextAlign.center,
                style: AppTheme.english(size: 16, color: AppColors.muted)),
          if (showEnglish && line.english.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(line.english,
                textAlign: TextAlign.center,
                style: AppTheme.english(size: 18, weight: FontWeight.w700)),
          ],
          if (onListen != null || onSaid != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onListen != null)
                  FilledButton.icon(
                    onPressed: onListen,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.ink,
                    ),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Listen'),
                  ),
                if (onListen != null && onSaid != null) const SizedBox(width: 12),
                if (onSaid != null)
                  FilledButton.icon(
                    onPressed: onSaid,
                    icon: const Icon(Icons.record_voice_over_rounded),
                    label: const Text('I said it!'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
