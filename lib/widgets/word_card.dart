import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'arabic_text.dart';

/// Sticker + Arabic word in a gender frame: blue = masculine, orange = feminine
/// with a small ة badge. The sticker stays on white.
class WordCard extends StatelessWidget {
  const WordCard({
    super.key,
    required this.sticker,
    required this.arabic,
    required this.isFeminine,
    this.english,
    this.phonetic,
    this.highlightLetter,
    this.onListen,
    this.stickerSize = 180,
    this.stickerOverride,
  });

  final String sticker; // asset path, e.g. assets/images/door.webp
  final String arabic; // shown exactly, full marks
  final bool isFeminine;
  final String? english;
  final String? phonetic;
  final String? highlightLetter;
  final VoidCallback? onListen;
  final double stickerSize;

  /// Optional replacement picture (e.g. a tinted or story image).
  final Widget? stickerOverride;

  @override
  Widget build(BuildContext context) {
    final frame = isFeminine ? AppColors.feminine : AppColors.masculine;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: frame, width: 5),
            boxShadow: [
              BoxShadow(color: frame.withAlpha(90), offset: const Offset(0, 6), blurRadius: 0),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: stickerSize,
                height: stickerSize,
                child: stickerOverride ??
                    Image.asset(
                      sticker,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('🖼️', style: TextStyle(fontSize: 64)),
                      ),
                    ),
              ),
              const SizedBox(height: 8),
              ArabicText(arabic, size: 44, highlightLetter: highlightLetter),
              if (phonetic != null && phonetic!.isNotEmpty)
                Text(phonetic!,
                    style: AppTheme.english(size: 16, color: AppColors.muted)),
              if (english != null && english!.isNotEmpty)
                Text(english!, style: AppTheme.english(size: 18, weight: FontWeight.w700)),
              if (onListen != null) ...[
                const SizedBox(height: 10),
                IconButton.filled(
                  onPressed: onListen,
                  tooltip: 'Listen',
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(AppTheme.minTap, AppTheme.minTap),
                  ),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ],
          ),
        ),
        if (isFeminine)
          Positioned(
            top: -12,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              decoration: BoxDecoration(
                color: AppColors.feminineBadge,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('ة',
                  textDirection: TextDirection.rtl,
                  style: AppTheme.arabic(size: 22, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}
