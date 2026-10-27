import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Arabic text, right-to-left, Baloo Bhaijaan 2, shown EXACTLY as given
/// (full vowel marks – never stripped).
///
/// [highlightLetter] colours that letter (with its marks) inside words, e.g. ب.
/// [highlightWords] colours whole words (e.g. the child's chosen adjective).
///
/// Joined letters stay joined: a zero-width joiner (ZWJ) is added on both sides
/// of a colour change, but only where the two letters really connect
/// (never after ا د ذ ر ز و ة ء, which don't join forward).
class ArabicText extends StatelessWidget {
  const ArabicText(
    this.text, {
    super.key,
    this.size = 32,
    this.color = AppColors.ink,
    this.weight = FontWeight.w700,
    this.highlightLetter,
    this.highlightWords = const [],
    this.highlightColor = AppColors.highlight,
    this.firstOnly = false,
    this.textAlign = TextAlign.center,
    this.maxLines,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final String? highlightLetter;
  final List<String> highlightWords;
  final Color highlightColor;
  final bool firstOnly; // colour only the first match of the letter
  final TextAlign textAlign;
  final int? maxLines;

  static const zwj = '\u200D';
  static const _marks = '\u064B\u064C\u064D\u064E\u064F\u0650\u0651\u0652\u0670';
  static const _noForwardJoin = 'اأإآٱدذرزوؤةءى';
  static const _alifForms = 'اأإآٱ';

  static bool _isArabicLetter(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return u >= 0x0621 && u <= 0x064A || u == 0x0671 || u == 0x0640;
  }

  static bool _joins(String prev, String next) =>
      _isArabicLetter(prev) &&
      !_noForwardJoin.contains(prev) &&
      _isArabicLetter(next) &&
      next != 'ء';

  static bool _sameLetter(String a, String target) {
    if (a == target) return true;
    // ا matches its hamza / madda forms; ه matches ة (so ة is coloured for ه lessons)
    if (_alifForms.contains(target) && _alifForms.contains(a)) return true;
    if (target == 'ه' && a == 'ة') return true;
    return false;
  }

  /// Split into [letter + its marks] clusters.
  static List<String> _clusters(String s) {
    final out = <String>[];
    for (final ch in s.split('')) {
      if (_marks.contains(ch) && out.isNotEmpty) {
        out[out.length - 1] += ch;
      } else {
        out.add(ch);
      }
    }
    return out;
  }

  /// Which clusters to colour.
  List<bool> _flags(List<String> cl) {
    final flags = List<bool>.filled(cl.length, false);

    // whole words
    for (final w in highlightWords.where((w) => w.trim().isNotEmpty)) {
      final wcl = _clusters(w.trim());
      for (var i = 0; i + wcl.length <= cl.length; i++) {
        var match = true;
        for (var k = 0; k < wcl.length; k++) {
          if (cl[i + k] != wcl[k]) {
            match = false;
            break;
          }
        }
        if (match) {
          for (var k = 0; k < wcl.length; k++) {
            flags[i + k] = true;
          }
        }
      }
    }

    // one letter
    final target = highlightLetter;
    if (target != null && target.isNotEmpty) {
      for (var i = 0; i < cl.length; i++) {
        if (_sameLetter(cl[i][0], target[0])) {
          flags[i] = true;
          if (firstOnly) break;
        }
      }
    }
    return flags;
  }

  List<InlineSpan> _spans(TextStyle base, TextStyle hl) {
    final cl = _clusters(text);
    if (cl.isEmpty) return const [];
    final flags = _flags(cl);
    if (!flags.contains(true)) return [TextSpan(text: text, style: base)];

    final spans = <InlineSpan>[];
    var buf = StringBuffer();
    var current = flags[0];

    for (var i = 0; i < cl.length; i++) {
      if (i > 0 && flags[i] != current) {
        // colour changes between cl[i-1] and cl[i]
        final bridge = _joins(cl[i - 1][0], cl[i][0]);
        if (bridge) buf.write(zwj);
        spans.add(TextSpan(text: buf.toString(), style: current ? hl : base));
        buf = StringBuffer();
        if (bridge) buf.write(zwj);
        current = flags[i];
      }
      buf.write(cl[i]);
    }
    spans.add(TextSpan(text: buf.toString(), style: current ? hl : base));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.arabic(size: size, color: color, weight: weight);
    final hl = base.copyWith(color: highlightColor);
    return Text.rich(
      TextSpan(children: _spans(base, hl)),
      textDirection: TextDirection.rtl,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
