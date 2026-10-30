// Parent Arabic Guide – loads assets/data/parent_guide.json once.
// Used by Screen 16 (Parent Corner). Home can show ParentGuide.cached?.todaysTip later.
import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;

import 'arabic_forms.dart';

class GuideGroup {
  final String id, title, icon;
  final int order;
  final Color color;
  const GuideGroup(this.id, this.title, this.icon, this.order, this.color);

  factory GuideGroup.fromJson(Map<String, dynamic> j) => GuideGroup(
        j['id'] as String,
        j['title'] as String,
        (j['icon'] ?? '') as String,
        (j['order'] ?? 0) as int,
        _hex((j['color'] ?? '#1A8FB0') as String),
      );

  static Color _hex(String h) =>
      Color(int.parse('FF${h.replaceFirst('#', '')}', radix: 16));
}

class GuideTip {
  final int id;
  final String group, title, rule, exampleAr, exampleSay, exampleEn;
  final String? girlLabel, girlAr, girlSay, replyAr, replySay;
  const GuideTip({
    required this.id,
    required this.group,
    required this.title,
    required this.rule,
    required this.exampleAr,
    required this.exampleSay,
    required this.exampleEn,
    this.girlLabel,
    this.girlAr,
    this.girlSay,
    this.replyAr,
    this.replySay,
  });

  factory GuideTip.fromJson(Map<String, dynamic> j) => GuideTip(
        id: j['id'] as int,
        group: j['group'] as String,
        title: j['title'] as String,
        rule: j['rule'] as String,
        exampleAr: (j['example_ar'] ?? '') as String,
        exampleSay: (j['example_say'] ?? '') as String,
        exampleEn: (j['example_en'] ?? '') as String,
        girlLabel: j['girl_label'] as String?,
        girlAr: j['girl_ar'] as String?,
        girlSay: j['girl_say'] as String?,
        replyAr: j['reply_ar'] as String?,
        replySay: j['reply_say'] as String?,
      );
}

class ParentGuide {
  final List<GuideGroup> groups;
  final List<GuideTip> tips;
  ParentGuide._(this.groups, this.tips);

  static ParentGuide? cached;

  static Future<ParentGuide> load() async {
    if (cached != null) return cached!;
    final raw = await rootBundle.loadString('assets/data/parent_guide.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final groups = (j['groups'] as List)
        .map((g) => GuideGroup.fromJson(g as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final tips = (j['tips'] as List)
        .map((t) => GuideTip.fromJson(t as Map<String, dynamic>))
        .toList();
    return cached = ParentGuide._(groups, tips);
  }

  /// Same rule as the design file: day of year (1 Jan = 1) % number of tips.
  int get todayIndex {
    if (tips.isEmpty) return 0;
    final n = DateTime.now();
    final dayOfYear = DateTime.utc(n.year, n.month, n.day)
        .difference(DateTime.utc(n.year, 1, 0))
        .inDays;
    return dayOfYear % tips.length;
  }

  GuideTip get todaysTip => tips[todayIndex];

  /// Tips in a group, with their index in [tips].
  List<(int, GuideTip)> tipsIn(String groupId) => [
        for (var i = 0; i < tips.length; i++)
          if (tips[i].group == groupId) (i, tips[i]),
      ];

  /// "a  b  c" → "a · b · c" (two or more spaces separate examples).
  static String dotted(String s) => s
      .split(RegExp(r'\s{2,}'))
      .where((p) => p.trim().isNotEmpty)
      .join('  ·  ');

  /// Arabic example → text for TTS: drops arrows, (English notes), slashes,
  /// joins the parts with a pause and removes sukun (golden rule 4).
  static String speakable(String ar) {
    final cleaned = ar
        .replaceAll('←', '  ')
        .replaceAll(RegExp(r'\([^)]*\)'), '  ')
        .replaceAll('/', '  ');
    final parts = cleaned
        .split(RegExp(r'\s{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    return ArabicForms.forSpeech(parts.join('، '));
  }
}
