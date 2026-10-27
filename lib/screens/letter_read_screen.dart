// Screen 5 – Read: letter shapes + "Where is ب hiding?" quiz
// Data: assets/data/lessons/<name>.json ("shapes", "posq") made by
// tools/lesson_to_json.py from the founder's lesson pages.
// Fallback (no lesson file yet): words from letter_positions.json.
// Route argument: the letter (String). Marks skill 'read' done at the end.

import 'package:flutter/material.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../data/audio_index.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';
import '../widgets/parent_tip.dart';

const _positions = ['beginning', 'middle', 'end'];
const _cardLabel = {
  'beginning': 'AT THE START',
  'middle': 'IN THE MIDDLE',
  'end': 'AT THE END',
};
const _quizLabel = {'beginning': 'Start', 'middle': 'Middle', 'end': 'End'};
const _sayPos = {
  'beginning': 'at the start',
  'middle': 'in the middle',
  'end': 'at the end',
};
const _parentTip =
    'Read from right to left together. Ask your child to point to the red letter in each word.';

class _ReadWord {
  final String word; // full marks, for display + TTS
  final String english;
  final String? emoji;
  final String? sticker;
  final String position; // beginning | middle | end
  final String? form; // ـبـ etc. (shapes only)
  const _ReadWord(this.word, this.english, this.emoji, this.sticker,
      this.position, this.form);
}

class LetterReadScreen extends StatefulWidget {
  const LetterReadScreen({super.key});

  @override
  State<LetterReadScreen> createState() => _LetterReadScreenState();
}

class _LetterReadScreenState extends State<LetterReadScreen> {
  final _repo = Repository.instance;
  final _audio = AudioService.instance;
  final _progress = ProgressService.instance;

  String? _letter;
  List<_ReadWord> _shapes = [];
  List<_ReadWord> _quiz = [];

  int _playing = -1; // shape card Juju is pointing at
  int _q = 0; // quiz question
  final Set<String> _tried = {}; // wrong answers on this question
  String? _rightAnswer; // shown green for a moment
  bool _finished = false;
  int _runId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_letter != null) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    _letter = arg is String ? arg : _progress.currentLetter;
    _load();
  }

  @override
  void dispose() {
    _runId++;
    _audio.stop();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────
  void _load() {
    final l = _letter!;
    final dynamic lesson = _repo.lesson(l);
    if (lesson is Map && lesson['shapes'] is List) {
      _shapes = [
        for (final s in lesson['shapes']) _fromJson(s, withForm: true)
      ];
      _quiz = [
        for (final q in (lesson['posq'] as List? ?? const []))
          _fromJson(q, positionKey: 'answer')
      ];
    } else {
      _fallback(l);
    }
  }

  _ReadWord _fromJson(dynamic m,
      {bool withForm = false, String positionKey = 'position'}) {
    return _ReadWord(
      '${m['word'] ?? m['plain'] ?? ''}',
      '${m['english'] ?? ''}',
      m['emoji'] as String?,
      m['sticker'] as String?,
      '${m[positionKey] ?? 'beginning'}',
      withForm ? m['form'] as String? : null,
    );
  }

  /// No lesson file yet (ا ب until you run the script): use letter_positions.json.
  void _fallback(String l) {
    final info = _repo.letterInfo(l);
    if (info == null) return;
    final joins = info.connects;
    final forms = {
      'beginning': joins ? '$lـ' : l,
      'middle': joins ? 'ـ$lـ' : 'ـ$l',
      'end': 'ـ$l',
    };
    for (final p in _positions) {
      final list = [for (final e in info.wordsAt(p)) _parse('$e', p)];
      if (list.isEmpty) continue;
      final first = list.first;
      _shapes.add(_ReadWord(
          first.word, first.english, null, first.sticker, p, forms[p]));
      _quiz.add(list.length > 1 ? list[1] : first);
    }
  }

  /// "بَاب (Door)" → word + english + hunt sticker.
  _ReadWord _parse(String s, String pos) {
    final m = RegExp(r'^(.*?)\s*\((.*)\)\s*$').firstMatch(s);
    final word = (m?.group(1) ?? s).trim();
    final en = (m?.group(2) ?? '').trim();
    String? sticker;
    for (final w in _repo.huntWords) {
      if (ArabicForms.strip(w.arabicWord) == ArabicForms.strip(word)) {
        sticker = w.sticker;
        break;
      }
    }
    return _ReadWord(word, en, null, sticker, pos, null);
  }

  String get _name => _repo.letterInfo(_letter!)?.name ?? _letter!;

  // ── Shapes: Juju points at each card with the audio ──────────
  Future<void> _showMe() async {
    final id = ++_runId;
    for (var i = 0; i < _shapes.length; i++) {
      if (!mounted || id != _runId) return;
      setState(() => _playing = i);
      await _sayWord(_shapes[i]);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (mounted && id == _runId) setState(() => _playing = -1);
  }

  Future<void> _sayWord(_ReadWord w) async {
    await _audio.stop();
    await Future.wait([
      AudioIndex.instance.playWord(w.word, sticker: w.sticker),
      Future.delayed(const Duration(milliseconds: 900)),
    ]);
  }

  // ── Quiz ──────────────────────────────────────────────────────
  Future<void> _answer(String pos) async {
    if (_rightAnswer != null || _tried.contains(pos)) return;
    final q = _quiz[_q];
    if (pos == q.position) {
      setState(() => _rightAnswer = pos);
      _progress.addStars(1);
      await _audio.say('Yes! $_name is ${_sayPos[pos]}!',
          voice: TtsVoice.jujuEnglish);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (_q + 1 >= _quiz.length) {
        _progress.markSkillDone(_letter!, 'read');
        _progress.addStars(2);
        setState(() => _finished = true);
        _audio.playAsset('juju/juju_en_skill_read_done.mp3');
      } else {
        setState(() {
          _q++;
          _tried.clear();
          _rightAnswer = null;
        });
        _sayWord(_quiz[_q]);
      }
    } else {
      setState(() => _tried.add(pos));
      _audio.say('Look again! Where is $_name?', voice: TtsVoice.jujuEnglish);
    }
  }

  void _back() {
    _runId++;
    _audio.stop();
    Navigator.maybePop(context);
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _topBar(),
            const SizedBox(height: 14),
            _header(),
            const SizedBox(height: 12),
            for (var i = 0; i < _shapes.length; i++) ...[
              _shapeCard(i),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            if (_quiz.isNotEmpty) (_finished ? _doneCard() : _quizCard()),
            const SizedBox(height: 16),
            ParentTip(
              text: _parentTip,
              onListen: () => _audio.say(_parentTip, voice: TtsVoice.parent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(children: [
      _circleButton(Icons.arrow_back_rounded, 'Back to My Letter', _back),
      Expanded(
        child: Text('📖 Read',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 24, weight: FontWeight.w800)),
      ),
      ListenableBuilder(
        listenable: _progress,
        builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 3))
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 24),
            const SizedBox(width: 4),
            Text('${_progress.stars}',
                style: AppTheme.english(size: 18, weight: FontWeight.w800)),
          ]),
        ),
      ),
    ]);
  }

  Widget _circleButton(IconData icon, String label, VoidCallback onTap,
      {double size = AppTheme.minTap, Color bg = AppColors.surface}) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: AppColors.ink, size: size * 0.45)),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      Juju(
        pose: _playing >= 0 ? JujuPose.pointDown : JujuPose.book,
        size: 96,
        motion: _playing >= 0 ? JujuMotion.bounce : JujuMotion.none,
        onTap: _showMe,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_name changes its shape!',
              style: AppTheme.english(size: 20, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          BigButton(
            label: 'Show me',
            emoji: '▶️',
            style: BigButtonStyle.accent,
            height: 64,
            onTap: _showMe,
          ),
        ]),
      ),
    ]);
  }

  Widget _picture(_ReadWord w, double size) {
    Widget emoji() => Center(
        child: Text(w.emoji ?? '🖼️', style: TextStyle(fontSize: size * 0.6)));
    return SizedBox(
      width: size,
      height: size,
      child: w.sticker == null
          ? emoji()
          : Image.asset(w.sticker!,
              fit: BoxFit.contain, errorBuilder: (_, __, ___) => emoji()),
    );
  }

  Widget _shapeCard(int i) {
    final w = _shapes[i];
    final active = i == _playing;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: active ? AppColors.accent : AppColors.surface, width: 3),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _sayWord(w),
        child: Row(children: [
          _picture(w, 64),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_cardLabel[w.position] ?? '',
                  style: AppTheme.english(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.muted)),
              Align(
                alignment: Alignment.centerLeft,
                child: ArabicText(w.word, size: 32, highlightLetter: _letter),
              ),
              Text(w.english,
                  style: AppTheme.english(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.muted)),
            ]),
          ),
          if (w.form != null)
            Container(
              width: 70,
              height: 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    ArabicText(w.form!, size: 38, color: AppColors.highlight),
              ),
            ),
          const SizedBox(width: 8),
          _circleButton(Icons.volume_up_rounded, 'Listen to ${w.english}',
              () => _sayWord(w),
              bg: AppColors.surface2),
        ]),
      ),
    );
  }

  Widget _quizCard() {
    final q = _quiz[_q];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('🎯 Where is ',
                      style:
                          AppTheme.english(size: 19, weight: FontWeight.w800)),
                  ArabicText(_letter!, size: 26, color: AppColors.highlight),
                  Text(' hiding?',
                      style:
                          AppTheme.english(size: 19, weight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          Text('${_q + 1} / ${_quiz.length}',
              style: AppTheme.english(
                  size: 14, weight: FontWeight.w700, color: AppColors.muted)),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _sayWord(q),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _picture(q, 80),
            const SizedBox(width: 12),
            Column(children: [
              ArabicText(q.word, size: 44), // no highlight: that's the question
              Text(q.english,
                  style: AppTheme.english(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.muted)),
            ]),
            const SizedBox(width: 8),
            _circleButton(
                Icons.volume_up_rounded, 'Hear the word', () => _sayWord(q),
                bg: AppColors.surface2),
          ]),
        ),
        const SizedBox(height: 14),
        // RTL row: "Start" sits on the RIGHT, like Arabic reading.
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(children: [
            for (final p in _positions) ...[
              if (p != _positions.first) const SizedBox(width: 8),
              Expanded(child: _answerButton(p)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _answerButton(String pos) {
    final right = _rightAnswer == pos;
    final dimmed = _tried.contains(pos);
    final bg = right ? AppColors.good : AppColors.surface;
    final shadow = right ? AppColors.goodShadow : AppColors.line;
    final fg = right ? Colors.white : AppColors.ink;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dimmed ? 0.4 : 1,
      child: Semantics(
        button: true,
        label: _quizLabel[pos],
        child: GestureDetector(
          onTap: () => _answer(pos),
          child: Container(
            height: AppTheme.minTap,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: right ? bg : AppColors.line, width: 2),
              boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 5))],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                right ? '${_quizLabel[pos]} ✓' : _quizLabel[pos]!,
                maxLines: 1,
                style: AppTheme.english(
                    size: 20, weight: FontWeight.w800, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Juju(pose: JujuPose.happy, size: 120, motion: JujuMotion.bounce),
        const SizedBox(height: 6),
        Text('You found every $_name! ⭐',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 22, weight: FontWeight.w800)),
        const SizedBox(height: 12),
        BigButton(
          label: 'Back to My Letter',
          style: BigButtonStyle.good,
          onTap: () {
            _audio.stop();
            Navigator.popUntil(context,
                (r) => r.settings.name == Routes.letterHub || r.isFirst);
          },
        ),
      ]),
    );
  }
}
