// lib/screens/letter_listen_screen.dart
// Screen 3 – Listen: meet the letter (name vs sound, dots), clap game, pairs.
// Data: assets/data/lessons/<name>.json  (words[], not_words[]);
// fallback: lesson_words.json for this letter + other open letters.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/audio_index.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';
import '../widgets/parent_tip.dart';

enum _Stage { meet, clap, pairs, done }

/// One word in the games (from a lesson file or lesson_words.json).
class _Item {
  final String arabic; // full marks, shown exactly
  final String english;
  final String emoji;
  final String phonetic;
  final String? sticker; // asset path
  final bool target; // starts with this week's letter?
  const _Item({
    required this.arabic,
    required this.english,
    required this.emoji,
    required this.phonetic,
    required this.sticker,
    required this.target,
  });

  /// Sticker id (file name without folder/extension) for AudioIndex.
  String? get stickerId {
    final s = sticker;
    if (s == null || s.isEmpty) return null;
    final name = s.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// Letter facts (letter metadata, not lesson words).
const Map<String, String> _dotText = {
  'ا': 'no dots',
  'ب': 'one dot below',
  'ت': 'two dots on top',
  'ث': 'three dots on top',
  'ج': 'one dot inside',
  'ح': 'no dots',
  'خ': 'one dot on top',
  'د': 'no dots',
  'ذ': 'one dot on top',
  'ر': 'no dots',
  'ز': 'one dot on top',
  'س': 'no dots',
  'ش': 'three dots on top',
  'ص': 'no dots',
  'ض': 'one dot on top',
  'ط': 'no dots',
  'ظ': 'one dot on top',
  'ع': 'no dots',
  'غ': 'one dot on top',
  'ف': 'one dot on top',
  'ق': 'two dots on top',
  'ك': 'no dots',
  'ل': 'no dots',
  'م': 'no dots',
  'ن': 'one dot on top',
  'ه': 'no dots',
  'و': 'no dots',
  'ي': 'two dots below',
};

const Map<String, String> _lookalikes = {
  'ب': 'ت ث ن',
  'ت': 'ب ث',
  'ث': 'ب ت',
  'ج': 'ح خ',
  'ح': 'ج خ',
  'خ': 'ج ح',
  'د': 'ذ',
  'ذ': 'د',
  'ر': 'ز',
  'ز': 'ر',
  'س': 'ش',
  'ش': 'س',
  'ص': 'ض',
  'ض': 'ص',
  'ط': 'ظ',
  'ظ': 'ط',
  'ع': 'غ',
  'غ': 'ع',
  'ف': 'ق',
  'ق': 'ف',
};

const Map<String, String> _soundHint = {
  'ا': 'a',
  'ب': 'b',
  'ت': 't',
  'ث': 'th (thin)',
  'ج': 'j',
  'ح': 'h (breathy)',
  'خ': 'kh',
  'د': 'd',
  'ذ': 'dh (as in "this")',
  'ر': 'r',
  'ز': 'z',
  'س': 's',
  'ش': 'sh',
  'ص': 's (heavy)',
  'ض': 'd (heavy)',
  'ط': 't (heavy)',
  'ظ': 'dh (heavy)',
  'ع': 'ʿa (from the throat)',
  'غ': 'gh',
  'ف': 'f',
  'ق': 'q',
  'ك': 'k',
  'ل': 'l',
  'م': 'm',
  'ن': 'n',
  'ه': 'h',
  'و': 'w',
  'ي': 'y',
};

const List<String> _praise = [
  'Yes! Great listening!',
  'Super ears!',
  'You got it!',
];

class LetterListenScreen extends StatefulWidget {
  const LetterListenScreen({super.key});

  @override
  State<LetterListenScreen> createState() => _LetterListenScreenState();
}

class _LetterListenScreenState extends State<LetterListenScreen> {
  final _rng = Random();
  String? _letter;
  String _letterName = '';

  List<_Item> _yes = [];
  List<_Item> _no = [];

  _Stage _stage = _Stage.meet;

  // Meet
  bool _heardName = false;
  bool _heardSound = false;

  // Clap game
  List<_Item> _clap = [];
  int _ci = 0;
  int _clapScore = 0;
  int _tries = 0;
  bool _revealed = false;
  bool? _wrongPick; // the button that faded (true = yes, false = no)
  bool _busy = false;

  // Pairs
  List<List<_Item>> _pairs = [];
  int _pi = 0;
  final Set<int> _heard = {};
  final Set<int> _pairWrong = {};
  int? _pairRight;

  bool _finishedOnce = false;

  // ---------------------------------------------------------------- setup

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_letter != null) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    final l = (arg is String && arg.isNotEmpty)
        ? arg
        : ProgressService.instance.currentLetter;
    _letter = Repository.baseLetter(l);
    _letterName = Repository.instance.letterInfo(_letter!)?.name ?? _letter!;
    _loadItems();
    _buildRounds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _jujuSay('This is $_letterName! Tap to hear its name and its sound.');
      }
    });
  }

  @override
  void dispose() {
    AudioService.instance.stop();
    super.dispose();
  }

  String get letter => _letter!;

  void _loadItems() {
    final dynamic lesson = Repository.instance.lesson(letter);
    if (lesson is Map) {
      _yes = _parseList(lesson['words'], true);
      _no = _parseList(lesson['not_words'], false);
    }
    if (_yes.isEmpty) {
      _yes = Repository.instance
          .lessonWordsFor(letter)
          .map((w) => _fromLessonWord(w, true))
          .toList();
    }
    if (_no.isEmpty) {
      for (final other in Repository.hackathonLetters) {
        if (other == letter) continue;
        _no.addAll(Repository.instance
            .lessonWordsFor(other)
            .take(2)
            .map((w) => _fromLessonWord(w, false)));
      }
      _no.shuffle(_rng);
    }
  }

  List<_Item> _parseList(dynamic raw, bool target) {
    if (raw is! List) return [];
    final out = <_Item>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final ar =
          (m['word'] ?? m['arabic'] ?? m['say'] ?? m['plain'] ?? '').toString();
      if (ar.isEmpty) continue;
      out.add(_Item(
        arabic: ar,
        english: (m['english'] ?? m['en'] ?? '').toString(),
        emoji: (m['emoji'] ?? m['e'] ?? '').toString(),
        phonetic: (m['phonetic'] ?? m['tr'] ?? '').toString(),
        sticker: _stickerPath(m['sticker']?.toString()),
        target: target,
      ));
    }
    return out;
  }

  _Item _fromLessonWord(dynamic w, bool target) => _Item(
        arabic: w.arabic as String,
        english: w.english as String,
        emoji: '',
        phonetic: (w.phonetic ?? '') as String,
        sticker: _stickerPath(w.sticker as String?),
        target: target,
      );

  String? _stickerPath(String? s) {
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('assets/')) return s;
    return 'assets/images/${s.endsWith('.webp') ? s : '$s.webp'}';
  }

  void _buildRounds() {
    // Clap: up to 5 letter words + 3 others, mixed (same shape as the pages).
    final yes = List<_Item>.of(_yes)..shuffle(_rng);
    final no = List<_Item>.of(_no)..shuffle(_rng);
    _clap = [...yes.take(5), ...no.take(3)]..shuffle(_rng);

    // Pairs: 3 rounds, one letter word vs one other word.
    _pairs = [];
    final n = min(3, min(yes.length, no.length));
    for (var i = 0; i < n; i++) {
      // reuse letter words from the end so pairs differ from early claps
      final y = yes[yes.length - 1 - i];
      _pairs.add([y, no[i]]..shuffle(_rng));
    }

    _ci = 0;
    _clapScore = 0;
    _tries = 0;
    _revealed = false;
    _wrongPick = null;
    _busy = false;
    _pi = 0;
    _heard.clear();
    _pairWrong.clear();
    _pairRight = null;
  }

  // ---------------------------------------------------------------- audio

  Future<void> _jujuSay(String english) async {
    await AudioService.instance.say(english, voice: TtsVoice.jujuEnglish);
  }

  Future<void> _playItem(_Item it) async {
    await AudioIndex.instance.playWord(it.arabic, sticker: it.stickerId);
  }

  Future<void> _playName() async {
    setState(() => _heardName = true);
    await AudioIndex.instance.playLetter(letter, withSound: false);
  }

  Future<void> _playSound() async {
    setState(() => _heardSound = true);
    // fatha syllable: أَ for alif, otherwise the letter + fatha
    final syllable = letter == 'ا' ? 'أَ' : '$letter\u064E';
    await AudioIndex.instance.playWord(syllable);
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  // ---------------------------------------------------------------- flow

  void _goClap() {
    if (_clap.isEmpty) {
      _goPairs();
      return;
    }
    setState(() => _stage = _Stage.clap);
    () async {
      await _jujuSay('Listen! Clap if the word starts with $_letterName.');
      if (mounted && _stage == _Stage.clap) _playItem(_clap[_ci]);
    }();
  }

  void _goPairs() {
    if (_pairs.isEmpty) {
      _finish();
      return;
    }
    setState(() => _stage = _Stage.pairs);
    _jujuSay(
        'Tap a picture to hear it. Then tap the one that starts with $_letterName.');
  }

  Future<void> _answerClap(bool saidYes) async {
    if (_busy || _revealed) return;
    final it = _clap[_ci];
    if (saidYes == it.target) {
      _busy = true;
      setState(() {
        _revealed = true;
        _wrongPick = null;
        _clapScore++;
      });
      await _jujuSay(_praise[_rng.nextInt(_praise.length)]);
      await _playItem(it);
      await _wait(700);
      _nextClap();
    } else {
      _tries++;
      setState(() => _wrongPick = saidYes);
      if (_tries >= 2) {
        _busy = true;
        setState(() => _revealed = true);
        await _jujuSay(it.target
            ? 'Great trying! This one starts with $_letterName.'
            : 'Great trying! This one does not start with $_letterName.');
        await _playItem(it);
        await _wait(900);
        _nextClap();
      } else {
        await _jujuSay('Hmm, listen again!');
        if (mounted) await _playItem(it);
      }
    }
  }

  void _nextClap() {
    if (!mounted) return;
    if (_ci + 1 >= _clap.length) {
      _busy = false;
      _goPairs();
      return;
    }
    setState(() {
      _ci++;
      _tries = 0;
      _revealed = false;
      _wrongPick = null;
      _busy = false;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && _stage == _Stage.clap) _playItem(_clap[_ci]);
    });
  }

  Future<void> _tapPair(int k) async {
    if (_busy) return;
    final it = _pairs[_pi][k];
    if (!_heard.contains(k)) {
      setState(() => _heard.add(k));
      await _playItem(it);
      return;
    }
    if (it.target) {
      _busy = true;
      setState(() => _pairRight = k);
      await _jujuSay(_praise[_rng.nextInt(_praise.length)]);
      await _playItem(it);
      await _wait(700);
      if (!mounted) return;
      if (_pi + 1 >= _pairs.length) {
        _busy = false;
        _finish();
        return;
      }
      setState(() {
        _pi++;
        _heard.clear();
        _pairWrong.clear();
        _pairRight = null;
        _busy = false;
      });
    } else {
      setState(() => _pairWrong.add(k));
      await _jujuSay('Listen to the other one!');
    }
  }

  Future<void> _finish() async {
    setState(() => _stage = _Stage.done);
    if (!_finishedOnce) {
      _finishedOnce = true;
      ProgressService.instance.markSkillDone(letter, 'listen');
      ProgressService.instance.addStars(2);
    }
    await AudioService.instance
        .playAsset('juju/juju_en_skill_listen_done.mp3', wait: true);
  }

  void _playAgain() {
    AudioService.instance.stop();
    setState(_buildRounds);
    _goClap();
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_letter == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _stepper(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: switch (_stage) {
                    _Stage.meet => _meetView(),
                    _Stage.clap => _clapView(),
                    _Stage.pairs => _pairsView(),
                    _Stage.done => _doneView(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: AppTheme.minTap,
            height: AppTheme.minTap,
            child: IconButton(
              iconSize: 32,
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 4),
          Text('🎧 Listen',
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(letter,
              style: AppTheme.arabic(
                  size: 30,
                  color: AppColors.highlight,
                  weight: FontWeight.w800)),
          const Spacer(),
          ListenableBuilder(
            listenable: ProgressService.instance,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: Text('⭐ ${ProgressService.instance.stars}',
                  style: AppTheme.english(size: 18, weight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    final idx = _stage.index; // meet 0, clap 1, pairs 2, done 3
    Widget chip(int i, String label) {
      final done = idx > i;
      final now = idx == i;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: done
                ? AppColors.good
                : now
                    ? AppColors.accent
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Text(done ? '✓ $label' : label,
              textAlign: TextAlign.center,
              style: AppTheme.english(
                  size: 15,
                  weight: FontWeight.w800,
                  color: done || now ? Colors.white : AppColors.muted)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [chip(0, 'Meet'), chip(1, 'Clap'), chip(2, 'Pick')]),
    );
  }

  /// Juju: headphones while waiting, talking while audio plays.
  Widget _juju({double size = 150}) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioService.instance.playing,
      builder: (_, talking, __) => Juju(
        pose: talking ? JujuPose.talking : JujuPose.headphones,
        size: size,
        motion: talking ? JujuMotion.wiggle : JujuMotion.none,
      ),
    );
  }

  // ---- Meet ----
  Widget _meetView() {
    final dots = _dotText[letter] ?? '';
    final twins = _lookalikes[letter];
    final sound = _soundHint[letter] ?? '';
    return Column(
      key: const ValueKey('meet'),
      children: [
        _juju(),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: _card(),
          child: Column(children: [
            Text(letter,
                textDirection: TextDirection.rtl,
                style: AppTheme.arabic(
                    size: 120,
                    color: AppColors.highlight,
                    weight: FontWeight.w800)),
            Text('$_letterName has $dots',
                style: AppTheme.english(
                    size: 18, weight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ).animate().fadeIn().scale(begin: const Offset(.9, .9)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: BigButton(
              label: 'Name: $_letterName',
              emoji: '🔊',
              style: BigButtonStyle.accent,
              onTap: _playName,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BigButton(
              label: 'Sound: $sound',
              emoji: '🔊',
              style: BigButtonStyle.white,
              onTap: _playSound,
            ),
          ),
        ]),
        const SizedBox(height: 18),
        if (_heardName || _heardSound)
          BigButton(
            label: 'Clap game!',
            emoji: '👏',
            style: BigButtonStyle.good,
            expand: true,
            onTap: _goClap,
          ).animate().fadeIn().slideY(begin: .3),
        const SizedBox(height: 18),
        ParentTip(
          title: 'Parent tip',
          text: 'The letter\'s name is "$_letterName", but its sound is just '
              '"$sound". Teachers focus on the sound. $_letterName has $dots.'
              '${twins != null ? ' Watch for $twins: they look similar but are different letters.' : ''}',
        ),
      ],
    );
  }

  // ---- Clap ----
  Widget _clapView() {
    final it = _clap[_ci];
    return Column(
      key: const ValueKey('clap'),
      children: [
        Text('Word ${_ci + 1} of ${_clap.length}   ·   👏 $_clapScore',
            style: AppTheme.english(
                size: 16, weight: FontWeight.w700, color: AppColors.muted)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _juju(size: 120),
            const SizedBox(width: 12),
            Expanded(child: _revealed ? _revealCard(it) : _listenCircle(it)),
          ],
        ),
        const SizedBox(height: 18),
        Text('Does it start with $_letterName?',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 22, weight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _ChoiceButton(
              emoji: '👏',
              label: 'Starts with',
              arabic: letter,
              color: AppColors.good,
              shadow: AppColors.goodShadow,
              faded: _wrongPick == true,
              glow: _revealed && it.target,
              onTap: () => _answerClap(true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ChoiceButton(
              emoji: '✋',
              label: 'No',
              arabic: letter,
              color: AppColors.blue,
              shadow: const Color(0xFF12657D),
              faded: _wrongPick == false,
              glow: _revealed && !it.target,
              onTap: () => _answerClap(false),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        ParentTip(
          title: 'Parent tip',
          text: 'Let their ears decide: the picture stays hidden until your '
              'child answers. Say the first sound slowly together.',
        ),
      ],
    );
  }

  Widget _listenCircle(_Item it) {
    return Center(
      child: GestureDetector(
        onTap: () => _playItem(it),
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: AppColors.accentShadow, offset: Offset(0, 6))
            ],
          ),
          alignment: Alignment.center,
          child: const Text('🔊', style: TextStyle(fontSize: 56)),
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
          begin: const Offset(1, 1),
          end: const Offset(1.05, 1.05),
          duration: 900.ms),
    );
  }

  Widget _revealCard(_Item it) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _card(border: it.target ? AppColors.good : AppColors.line),
      child: Column(children: [
        _Sticker(item: it, size: 90),
        const SizedBox(height: 4),
        ArabicText(
          it.arabic,
          size: 34,
          highlightLetter: it.target ? letter : null,
          firstOnly: true,
        ),
        Text('${it.phonetic} · ${it.english}',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 15, color: AppColors.muted, weight: FontWeight.w600)),
      ]),
    ).animate().fadeIn().scale(begin: const Offset(.85, .85));
  }

  // ---- Pairs ----
  Widget _pairsView() {
    final opts = _pairs[_pi];
    return Column(
      key: ValueKey('pairs$_pi'),
      children: [
        _juju(size: 120),
        Text('Which one starts with $_letterName?',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 22, weight: FontWeight.w800)),
        Text(
            'Tap to hear. Tap again to choose.  (${_pi + 1} of ${_pairs.length})',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 15, color: AppColors.muted, weight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(
          children: List.generate(opts.length, (k) {
            final it = opts[k];
            final right = _pairRight == k;
            final faded = _pairWrong.contains(k);
            final heard = _heard.contains(k);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Opacity(
                  opacity: faded ? .4 : 1,
                  child: GestureDetector(
                    onTap: () => _tapPair(k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: _card(
                        border: right
                            ? AppColors.good
                            : heard
                                ? AppColors.accent
                                : AppColors.line,
                        width: right || heard ? 4 : 2,
                      ),
                      child: Column(children: [
                        _Sticker(item: it, size: 110),
                        const SizedBox(height: 6),
                        ArabicText(
                          it.arabic,
                          size: 30,
                          highlightLetter: right ? letter : null,
                          firstOnly: true,
                        ),
                        if (right)
                          const Text('⭐', style: TextStyle(fontSize: 28))
                              .animate()
                              .scale(duration: 400.ms),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ---- Done ----
  Widget _doneView() {
    return Column(
      key: const ValueKey('done'),
      children: [
        const SizedBox(height: 12),
        Juju(pose: JujuPose.rewardStar, size: 200, motion: JujuMotion.bounce),
        const SizedBox(height: 8),
        Text('Super listening!',
            style: AppTheme.english(
                size: 30, weight: FontWeight.w800, color: AppColors.good)),
        Text('👏 $_clapScore / ${_clap.length}   ·   +2 ⭐',
            style: AppTheme.english(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 24),
        BigButton(
          label: 'Back to my letter',
          emoji: '📖',
          style: BigButtonStyle.accent,
          expand: true,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'Play again',
          emoji: '🔁',
          style: BigButtonStyle.white,
          expand: true,
          onTap: _playAgain,
        ),
        const SizedBox(height: 18),
        ParentTip(
          title: 'Parent tip',
          text: 'Replay the games tomorrow. Repetition is what makes it stick.',
        ),
      ],
    );
  }

  BoxDecoration _card({Color border = AppColors.line, double width = 2}) =>
      BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: border, width: width),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 5))
        ],
      );
}

// ------------------------------------------------------------------ widgets

class _Sticker extends StatelessWidget {
  final _Item item;
  final double size;
  const _Sticker({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget emoji() => SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(item.emoji.isNotEmpty ? item.emoji : '🔊',
                style: TextStyle(fontSize: size * .6)),
          ),
        );
    final s = item.sticker;
    if (s == null) return emoji();
    return Image.asset(s,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => emoji());
  }
}

class _ChoiceButton extends StatelessWidget {
  final String emoji, label, arabic;
  final Color color, shadow;
  final bool faded, glow;
  final VoidCallback onTap;
  const _ChoiceButton({
    required this.emoji,
    required this.label,
    required this.arabic,
    required this.color,
    required this.shadow,
    required this.faded,
    required this.glow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final btn = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: faded ? .35 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 104,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: glow ? AppColors.accent : Colors.transparent,
              width: 5,
            ),
            boxShadow: [
              BoxShadow(
                  color: shadow,
                  offset: Offset(0, AppTheme.shadowDepth.toDouble()))
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 38)),
                FittedBox(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label,
                        style: AppTheme.english(
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(width: 6),
                    Text(arabic,
                        style: AppTheme.arabic(
                            size: 24,
                            weight: FontWeight.w800,
                            color: Colors.white)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return glow ? btn.animate().shake(hz: 3, duration: 400.ms) : btn;
  }
}
