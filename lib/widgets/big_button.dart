import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

enum BigButtonStyle {
  accent(AppColors.accent, AppColors.accentShadow, AppColors.ink), // My Letter, Listen
  good(AppColors.good, AppColors.goodShadow, Colors.white), // Treasure Hunt, Say it!
  blue(AppColors.blue, Color(0xFF136A83), Colors.white), // links, passport
  white(AppColors.surface, AppColors.line, AppColors.ink); // quiet actions

  const BigButtonStyle(this.fill, this.shadow, this.text);
  final Color fill;
  final Color shadow;
  final Color text;
}

/// The kids' button: big, rounded, solid bottom shadow, presses down when tapped.
/// Give it an emoji or icon plus a short label.
class BigButton extends StatefulWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.emoji,
    this.icon,
    this.style = BigButtonStyle.accent,
    this.height = 72,
    this.expand = true,
    this.fontSize = 22,
    this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final String? emoji;
  final IconData? icon;
  final BigButtonStyle style;
  final double height; // ≥ 64
  final bool expand;
  final double fontSize;

  /// Optional custom content (e.g. an ArabicText). Replaces emoji + label.
  final Widget? child;

  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final enabled = widget.onTap != null;
    final depth = _down ? 1.0 : AppTheme.shadowDepth;

    final content = widget.child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.emoji != null)
              Text(widget.emoji!, style: TextStyle(fontSize: widget.fontSize + 4)),
            if (widget.icon != null)
              Icon(widget.icon, color: s.text, size: widget.fontSize + 6),
            if (widget.emoji != null || widget.icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.english(
                    size: widget.fontSize, color: s.text, weight: FontWeight.w800),
              ),
            ),
          ],
        );

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      height: widget.height.clamp(AppTheme.minTap, 200).toDouble(),
      margin: EdgeInsets.only(top: AppTheme.shadowDepth - depth, bottom: depth),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: enabled ? s.fill : s.fill.withAlpha(128),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: s == BigButtonStyle.white
            ? Border.all(color: AppColors.line, width: 2)
            : null,
        boxShadow: [BoxShadow(color: s.shadow, offset: Offset(0, depth), blurRadius: 0)],
      ),
      alignment: Alignment.center,
      child: content,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: widget.child == null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
      ),
    );
  }
}

/// Parents' gate: the child must hold for [seconds] (default 3) before it opens.
/// A ring fills while holding; letting go early resets it.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.onComplete,
    this.label = 'Parents',
    this.hint = 'Hold for 3 seconds',
    this.seconds = 3,
    this.icon = Icons.lock_outline,
  });

  final VoidCallback onComplete;
  final String label;
  final String hint;
  final int seconds;
  final IconData icon;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        _c.reset();
        widget.onComplete();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.hint}',
      child: GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) => _c.reverse(),
        onTapCancel: () => _c.reverse(),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _c.value,
                        strokeWidth: 4,
                        backgroundColor: AppColors.line,
                        color: AppColors.blue,
                      ),
                      Icon(widget.icon, size: 18, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: AppTheme.english(size: 16, weight: FontWeight.w700)),
                  Text(widget.hint,
                      style: AppTheme.english(size: 13, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
