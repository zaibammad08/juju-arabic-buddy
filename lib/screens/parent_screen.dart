// Screen 16 – Parent Corner (opened from Home after the hold-3-s gate).
// Tabs: Progress (skills per letter + Muse Spark weekly report) ·
//       Arabic guide (55 tips from parent_guide.json, today's tip on top) ·
//       Ask Juju (lesson questions only, 2–3 sentences, Muse Spark).
// Settings (gear): privacy notes + reset progress.
import 'package:flutter/material.dart';

import '../data/parent_guide.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/meta_text.dart';
import '../services/progress.dart';
import '../theme/app_theme.dart';
import '../widgets/juju.dart';

enum _Tab { progress, guide, ask }

/// Brown text used on the yellow tip cards in the design file.
const _tipInk = Color(0xFF8A5A00);

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});
  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  _Tab _tab = _Tab.progress;

  // Guide
  ParentGuide? _guide;
  bool _guideFailed = false;
  int _shown = 0;
  String? _openGroup;

  // Weekly report
  bool _reportLoading = false;
  String? _report;

  // Ask Juju
  final _askCtrl = TextEditingController();
  bool _asking = false;
  String? _askedQ;
  String? _answer;

  static const _skills = ['listen', 'speak', 'read', 'write'];
  static const _skillEmoji = {
    'listen': '👂',
    'speak': '🗣️',
    'read': '📖',
    'write': '✍️',
  };

  ProgressService get _progress => ProgressService.instance;
  // ignore: dead_null_aware_expression
  String get _letter =>
      _progress.currentLetter ?? Repository.hackathonLetters.first;

  @override
  void initState() {
    super.initState();
    ParentGuide.load().then((g) {
      if (!mounted) return;
      setState(() {
        _guide = g;
        _shown = g.todayIndex;
        _openGroup = g.todaysTip.group;
      });
    }).catchError((_) {
      if (mounted) setState(() => _guideFailed = true);
    });
  }

  @override
  void dispose() {
    AudioService.instance.stop();
    _askCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers
  int _count(dynamic v) {
    if (v is int) return v;
    if (v is Iterable) return v.length;
    if (v is Map) return v.length;
    return 0;
  }

  void _sayEnglish(String text) =>
      AudioService.instance.say(text, voice: TtsVoice.parent);

  void _sayArabic(String ar) => AudioService.instance
      .say(ParentGuide.speakable(ar), voice: TtsVoice.lesson);

  // ---------------------------------------------------------------- actions
  Future<void> _makeReport() async {
    if (_reportLoading) return;
    setState(() => _reportLoading = true);
    String text;
    try {
      final r = await MetaText.instance.parentReport(_progress.summary());
      final s = r.toString().trim();
      text = s.isEmpty ? _localReport() : s;
    } catch (_) {
      text = _localReport();
    }
    if (!mounted) return;
    setState(() {
      _report = text;
      _reportLoading = false;
    });
  }

  /// Fallback when Muse Spark is offline: plain facts only.
  String _localReport() {
    final done = <String>[];
    for (final l in Repository.hackathonLetters) {
      final n = _skills
          .where((s) => _progress.skillState(l, s) == SkillState.done)
          .length;
      if (n > 0) done.add('$l: $n of 4 skills');
    }
    return 'This week your child earned ${_progress.stars} stars and found '
        '${_count(_progress.wordsFound)} words at home. '
        '${done.isEmpty ? 'No letter skills are finished yet – try one skill today.' : 'Letters practised: ${done.join(', ')}.'}';
  }

  String _lessonContext() {
    final words = Repository.instance
        .lessonWordsFor(_letter)
        .take(6)
        .map((w) => '${w.arabic} = ${w.english}')
        .join(', ');
    return "This week's letter: $_letter. Lesson words: $words. "
        'School Arabic (MSA) for Year 1.';
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _askCtrl.text).trim();
    if (q.isEmpty || _asking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _asking = true;
      _askedQ = q;
      _answer = null;
    });
    String a;
    try {
      final r =
          await MetaText.instance.askJuju(q, lessonContext: _lessonContext());
      final s = r.toString().trim();
      a = s.isEmpty
          ? "Sorry, I couldn't answer that right now. Please try again in a moment."
          : s;
    } catch (_) {
      a = "Sorry, I couldn't answer that right now. Please try again in a moment.";
    }
    if (!mounted) return;
    setState(() {
      _answer = a;
      _asking = false;
    });
    _askCtrl.clear();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings & privacy',
                  style: AppTheme.english(size: 20, weight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final line in const [
                '📷 Photos are checked, then deleted. They are never saved.',
                '🎙️ Your child\'s voice is only used to check the word, then discarded.',
                '💛 Feelings games are never stored.',
                '🔒 Progress stays on this device.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line,
                      style:
                          AppTheme.english(size: 15, color: AppColors.muted)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: Text('Reset all progress',
                      style:
                          AppTheme.english(size: 16, weight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.line, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius)),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: const Text('Reset progress?'),
                        content: const Text(
                            'Stars, skills, stickers and the writing wall will be cleared. This cannot be undone.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      _progress.resetAll();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) setState(() => _report = null);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 12),
              _tabs(),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_tab) {
                  _Tab.progress => _progressTab(),
                  _Tab.guide => _guideTab(),
                  _Tab.ask => _askTab(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(
          {required IconData icon,
          required String label,
          required VoidCallback onTap}) =>
      Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 2))
                ],
              ),
              child: Icon(icon, color: AppColors.ink),
            ),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          _roundButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back to home',
              onTap: () => Navigator.maybePop(context)),
          Expanded(
            child: Column(
              children: [
                Text('Parent Corner',
                    style: AppTheme.english(size: 20, weight: FontWeight.w800)),
                Text('Arabic basics, in plain English',
                    style: AppTheme.english(
                        size: 13,
                        color: AppColors.muted,
                        weight: FontWeight.w600)),
              ],
            ),
          ),
          _roundButton(
              icon: Icons.settings_rounded,
              label: 'Settings',
              onTap: _openSettings),
        ],
      );

  Widget _tabs() {
    Widget pill(_Tab t, String label) {
      final on = _tab == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: AppTheme.english(
                    size: 15,
                    weight: FontWeight.w700,
                    color: on ? Colors.white : AppColors.ink)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.line, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        pill(_Tab.progress, 'Progress'),
        pill(_Tab.guide, 'Arabic guide'),
        pill(_Tab.ask, 'Ask Juju'),
      ]),
    );
  }

  BoxDecoration get _card => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 3))
        ],
      );

  Widget _listen(VoidCallback onTap, {String label = 'Listen'}) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent, width: 2),
            ),
            child: const Icon(Icons.volume_up_rounded,
                size: 20, color: AppColors.ink),
          ),
        ),
      );

  /// Yellow tip card with a left accent stripe (non-uniform border → clip).
  Widget _tipCard({required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: AppColors.tip,
            border: Border(left: BorderSide(color: AppColors.accent, width: 5)),
          ),
          child: child,
        ),
      );

  // ============================================================ PROGRESS
  Widget _progressTab() => ListenableBuilder(
        listenable: _progress,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Row(children: [
              _stat('⭐', '${_progress.stars}', 'stars'),
              const SizedBox(width: 8),
              _stat('🧸', '${_count(_progress.wordsFound)}', 'words found'),
              const SizedBox(width: 8),
              _stat('📅', '${_count(_progress.daysActive)}', 'days active'),
            ]),
            const SizedBox(height: 12),
            Container(
              decoration: _card,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Skills per letter',
                      style:
                          AppTheme.english(size: 17, weight: FontWeight.w800)),
                  Text('👂 Listen · 🗣️ Speak · 📖 Read · ✍️ Write',
                      style:
                          AppTheme.english(size: 13, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  for (final l in Repository.hackathonLetters) _letterRow(l),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _reportCard(),
            const SizedBox(height: 12),
            if (_guide != null) _todayTeaser(),
          ],
        ),
      );

  Widget _stat(String emoji, String value, String label) => Expanded(
        child: Container(
          decoration: _card,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Text('$emoji $value',
                style: AppTheme.english(size: 20, weight: FontWeight.w800)),
            Text(label,
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 13, color: AppColors.muted, weight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _letterRow(String l) {
    final current = l == _letter;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: current ? AppColors.tip : AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: current ? AppColors.accent : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(l,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: AppTheme.arabic(
                    size: 28,
                    color: current ? AppColors.highlight : AppColors.ink,
                    weight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          for (final s in _skills) Expanded(child: _skillChip(l, s)),
          SizedBox(
            width: 30,
            child: Text(_progress.hasBadge(l) ? '🏅' : '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  Widget _skillChip(String letter, String skill) {
    final st = _progress.skillState(letter, skill);
    final (bg, fg, mark) = switch (st) {
      SkillState.done => (AppColors.good, Colors.white, '✓'),
      SkillState.next => (AppColors.surface, AppColors.highlight, 'NEXT'),
      SkillState.todo => (AppColors.surface, AppColors.muted, '·'),
    };
    return Semantics(
      label: '$skill: ${st.name}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: st == SkillState.done ? AppColors.good : AppColors.line,
              width: 1.5),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${_skillEmoji[skill]} $mark',
                style: AppTheme.english(
                    size: 14, weight: FontWeight.w800, color: fg)),
          ),
        ),
      ),
    );
  }

  Widget _reportCard() => _tipCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text("THIS WEEK'S REPORT",
                    style: AppTheme.english(
                        size: 12, weight: FontWeight.w800, color: _tipInk)),
              ),
              if (_report != null) _listen(() => _sayEnglish(_report!)),
            ]),
            const SizedBox(height: 6),
            if (_reportLoading)
              Row(children: [
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 10),
                Text('Juju is writing your report…',
                    style: AppTheme.english(size: 15, weight: FontWeight.w600)),
              ])
            else if (_report != null)
              Text(_report!,
                  style: AppTheme.english(size: 15, weight: FontWeight.w500))
            else
              Text(
                  'A short summary of what your child practised, and one idea for today.',
                  style: AppTheme.english(size: 15, weight: FontWeight.w500)),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius)),
                ),
                onPressed: _reportLoading ? null : _makeReport,
                child: Text(
                    _report == null ? 'Make my report ✨' : 'Make it again',
                    style: AppTheme.english(size: 16, weight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                'Written by Muse Spark from progress numbers only – no photos or recordings.',
                style: AppTheme.english(size: 12, color: AppColors.muted)),
          ],
        ),
      );

  Widget _todayTeaser() {
    final t = _guide!.todaysTip;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        _tab = _Tab.guide;
        _shown = _guide!.todayIndex;
        _openGroup = t.group;
      }),
      child: Container(
        decoration: _card,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TODAY'S ARABIC TIP",
                    style: AppTheme.english(
                        size: 12,
                        weight: FontWeight.w800,
                        color: AppColors.blue)),
                Text(t.title,
                    style: AppTheme.english(size: 17, weight: FontWeight.w800)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      ),
    );
  }

  // ============================================================ GUIDE
  Widget _guideTab() {
    if (_guideFailed) {
      return Center(
          child: Text('The guide could not load. Please restart the app.',
              style: AppTheme.english(size: 15, color: AppColors.muted)));
    }
    final g = _guide;
    if (g == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(key: ValueKey(_shown), child: _guideCard(g)),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [for (final grp in g.groups) _groupCard(g, grp)],
          ),
        ),
      ],
    );
  }

  Widget _guideCard(ParentGuide g) {
    final t = g.tips[_shown];
    final isToday = _shown == g.todayIndex;
    return _tipCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(isToday ? "TODAY'S GUIDE" : 'GUIDE',
                  style: AppTheme.english(
                      size: 12, weight: FontWeight.w800, color: _tipInk)),
            ),
            Text('${_shown + 1} of ${g.tips.length}',
                style: AppTheme.english(
                    size: 12, weight: FontWeight.w700, color: _tipInk)),
            if (!isToday)
              TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.only(left: 8),
                    foregroundColor: _tipInk),
                onPressed: () => setState(() {
                  _shown = g.todayIndex;
                  _openGroup = g.todaysTip.group;
                }),
                child: Text("· Today's",
                    style: AppTheme.english(size: 12, weight: FontWeight.w800)
                        .copyWith(decoration: TextDecoration.underline)),
              ),
          ]),
          Text(t.title,
              style: AppTheme.english(size: 18, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(t.rule,
              style: AppTheme.english(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(children: [
            if (t.audio) ...[
              _listen(() => _sayArabic(t.exampleAr),
                  label: 'Listen to the example'),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(ParentGuide.dotted(t.exampleAr),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: AppTheme.arabic(size: 24, weight: FontWeight.w700)),
            ),
          ]),
          Text(
              '${ParentGuide.dotted(t.exampleSay)}  →  ${ParentGuide.dotted(t.exampleEn)}',
              style: AppTheme.english(size: 13, weight: FontWeight.w700)),
          if (t.girlAr != null)
            _extraRow(t.girlLabel ?? 'To a girl', t.girlAr!, t.girlSay ?? '',
                t.audio),
          if (t.replyAr != null)
            _extraRow('Reply', t.replyAr!, t.replySay ?? '', t.audio),
        ],
      ),
    );
  }

  Widget _extraRow(String label, String ar, String say, bool audio) =>
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.only(top: 6),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE8C77A)))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: AppTheme.english(
                        size: 11, weight: FontWeight.w800, color: _tipInk)),
                Text(say,
                    style: AppTheme.english(size: 13, weight: FontWeight.w700)),
              ],
            ),
          ),
          Text(ar,
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(size: 20, weight: FontWeight.w700)),
          if (audio) ...[
            const SizedBox(width: 8),
            _listen(() => _sayArabic(ar), label: 'Listen: $label'),
          ],
        ]),
      );

  Widget _groupCard(ParentGuide g, GuideGroup grp) {
    final items = g.tipsIn(grp.id);
    final open = _openGroup == grp.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _openGroup = open ? null : grp.id),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: grp.color,
                      borderRadius: BorderRadius.circular(11)),
                  child: Text(grp.icon,
                      textDirection: TextDirection.rtl,
                      style: AppTheme.arabic(
                          size: 15,
                          color: Colors.white,
                          weight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(grp.title,
                      style:
                          AppTheme.english(size: 17, weight: FontWeight.w800)),
                ),
                Text('${items.length}',
                    style: AppTheme.english(
                        size: 13,
                        color: AppColors.muted,
                        weight: FontWeight.w700)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded,
                      color: AppColors.muted),
                ),
              ]),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (final (i, tip) in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _tipItem(i, tip),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tipItem(int i, GuideTip tip) {
    final sel = i == _shown;
    return Material(
      color: sel ? AppColors.tip : AppColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: sel ? AppColors.accent : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _shown = i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            SizedBox(
              width: 24,
              child: Text('${tip.id}',
                  style: AppTheme.english(
                      size: 12,
                      weight: FontWeight.w800,
                      color: AppColors.muted)),
            ),
            Expanded(
              child: Text(tip.title,
                  style: AppTheme.english(size: 15, weight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  // ============================================================ ASK JUJU
  Widget _askTab() {
    final suggestions = [
      'How do I say the $_letter sound?',
      'How can I practise this letter at home?',
      'What do the little marks above letters mean?',
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Juju(
              pose: _asking ? JujuPose.thinking : JujuPose.book,
              size: 110,
              motion: _asking ? JujuMotion.wiggle : JujuMotion.none),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: _card,
              padding: const EdgeInsets.all(12),
              child: Text(
                  "Ask me about this week's lessons. I'll answer in 2–3 short sentences.",
                  style: AppTheme.english(size: 15, weight: FontWeight.w600)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s,
                    style: AppTheme.english(size: 13, weight: FontWeight.w600)),
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.line),
                onPressed: _asking ? null : () => _ask(s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _card,
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _askCtrl,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ask(),
                style: AppTheme.english(size: 16),
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    hintText: 'Type your question…'),
              ),
            ),
            IconButton.filled(
              tooltip: 'Ask Juju',
              iconSize: 24,
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.good,
                  minimumSize: const Size(48, 48)),
              onPressed: _asking ? null : () => _ask(),
              icon: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_askedQ != null)
          _tipCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_askedQ!,
                    style: AppTheme.english(
                        size: 13, weight: FontWeight.w700, color: _tipInk)),
                const SizedBox(height: 6),
                if (_asking)
                  Text('Juju is thinking…',
                      style:
                          AppTheme.english(size: 15, weight: FontWeight.w600))
                else if (_answer != null)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(_answer!,
                          style: AppTheme.english(
                              size: 15, weight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    _listen(() => _sayEnglish(_answer!)),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
            'Juju only answers questions about the lessons. For anything else, please ask your child\'s teacher.',
            style: AppTheme.english(size: 12, color: AppColors.muted)),
      ],
    );
  }
}
