// Drop-in top section for the "You found it!" screen:
// room background + chest reveal, then the word card fades in.
// Keep your existing Listen / Say it / Next buttons below this widget,
// and enable them when onRevealed fires.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../screens/magic/magic_common.dart'; // arabicLine, RoundIcon
import 'chest_reveal.dart';
import 'room_backdrop.dart';

class HuntFoundReveal extends StatefulWidget {
  final Future<void> ready; // your Muse Spark call
  final Uint8List photo;
  final Widget sticker; // e.g. StickerImage(path, size: 200)
  final String arabic;
  final String transliteration;
  final String english;
  final VoidCallback onListen;
  final VoidCallback? onRevealed;
  final VoidCallback? onFailed;

  const HuntFoundReveal({
    super.key,
    required this.ready,
    required this.photo,
    required this.sticker,
    required this.arabic,
    required this.transliteration,
    required this.english,
    required this.onListen,
    this.onRevealed,
    this.onFailed,
  });

  @override
  State<HuntFoundReveal> createState() => _HuntFoundRevealState();
}

class _HuntFoundRevealState extends State<HuntFoundReveal> {
  bool _revealed = false;

  void _done() {
    setState(() => _revealed = true);
    widget.onListen(); // say the word as it lands
    widget.onRevealed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 380,
        child: RoomBackdrop(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ChestReveal(
              height: 380,
              ready: widget.ready,
              photo: widget.photo,
              sticker: widget.sticker,
              onRevealed: _done,
              onFailed: widget.onFailed,
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: _revealed ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          offset: _revealed ? Offset.zero : const Offset(0, 0.15),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(color: AppColors.line, offset: Offset(0, 4))
              ],
            ),
            child: Row(children: [
              RoundIcon(
                  icon: Icons.volume_up_rounded,
                  label: 'Hear the word',
                  onTap: widget.onListen,
                  color: AppColors.accent,
                  shadow: AppColors.accentShadow),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      arabicLine(widget.arabic, size: 48),
                      Text(widget.transliteration,
                          style: AppTheme.english(
                              size: 18,
                              weight: FontWeight.w700,
                              color: AppColors.muted)),
                      Text(widget.english,
                          style: AppTheme.english(
                              size: 20, weight: FontWeight.w800)),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
