// Screen 12 – Core sentences (`Routes.sentences`)
//
// Used when a child skips "Make it yours": the 5 ready-made sentences for the
// found word from sentence_bank.json (هَذَا… / عِنْدِي… / أَنَا أَرَى… / … / أَيْنَ…؟),
// one at a time, with word-by-word English, Listen + "I said it! ⭐".
// Last sentence → sticker goes to My Arabic Room (Screen 13).
//
// Open with:  Navigator.pushNamed(context, Routes.sentences, arguments: word.id);
// (arguments may also be a HuntWord or {'wordId': 'door'})

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/parent_tip.dart';

class SentenceScreen extends StatefulWidget {
  const SentenceScreen({super.key});

  @override
  State<SentenceScreen> createState() => _SentenceScreenState();
}

/// One sentence from sentence_bank.json, read from the raw map so the
/// `template` id (needed for word-by-word English) is kept.
class _Line {
  final String template, arabic, audioText, phonetic, english, audio;
  const _Line(this.template, this.arabic, this.audioText, this.phonetic,
      this.english, this.audio);

  factory _Line.fromMap(Map m) => _Line(
        '${m['template'] ?? ''}',
        '${m['arabic'] ?? ''}',
        '${m['audio_text'] ?? m['arabic'] ?? ''}',
        '${m['phonetic'] ?? ''}',
        '${m['english'] ?? ''}',
        '${m['audio'] ?? ''}',
      );
}

/// One Arabic chunk + its English gloss (shown under it).
class _Gloss {
  final String arabic, english;
  const _Gloss(this.arabic, this.english);
}

class _SentenceScreenState extends State<SentenceScreen> {
  String? _wordId;
  Map _word = const {};
  List<_Line> _lines = const [];
  int _index = 0;
  bool _finished = false;
  bool _busy = false;
  int _run = 0; // bumps on every new audio sequence, so old ones stop

  final _audio = AudioService.instance;
  final _progress = ProgressService.instance;

  // ---------- data ----------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wordId != null) return;
    _load(ModalRoute.of(context)?.settings.arguments);
  }

  void _load(Object? arg) {
    final repo = Repository.instance;
    String? id;
    if (arg is String) {
      id = arg;
    } else if (arg is Map) {
      id = (arg['wordId'] ?? arg['id'])?.toString();
    } else if (arg is HuntWord) {
      id = arg.id;
    }
    id ??= repo.sentenceBank.isNotEmpty ? repo.sentenceBank.first.id : 'door';
    _wordId = id;

    final entry = repo.bankEntry(id);
    if (entry == null) return;
    final raw = entry.raw;
    final hunt = repo.huntWord(id);
    // hunt word raw has en_indef / en_def / en_plural; bank raw has the basics
    _word = {...raw, if (hunt != null) ...hunt.raw};
    _lines = ((raw['sentences'] as List?) ?? const [])
        .whereType<Map>()
        .map(_Line.fromMap)
        .where((l) => l.arabic.isNotEmpty)
        .toList();

    // first sentence plays by itself
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _playSentence(intro: true));
  }

  String get _englishWord => '${_word['english_word'] ?? ''}'.toLowerCase();

  String get _indef {
    final v = _word['en_indef'];
    if (v is String && v.isNotEmpty) return v;
    final w = _englishWord;
    if (w.isEmpty) return '';
    return '${'aeiou'.contains(w[0]) ? 'an' : 'a'} $w';
  }

  String get _def {
    final v = _word['en_def'];
    if (v is String && v.isNotEmpty) return v;
    return 'the $_englishWord';
  }

  String get _be => _word['en_plural'] == true ? 'are' : 'is';

  String get _stickerPath {
    final s = '${_word['sticker'] ?? ''}';
    if (s.startsWith('assets/')) return s;
    return 'assets/images/${s.isNotEmpty ? s : _wordId}.webp';
  }

  /// Word-by-word English. The template tells which Arabic words come before
  /// the noun; everything after them is the noun phrase (works for idafa
  /// words like فُرْشَاةُ أَسْنَانٍ too). Returns null if it doesn't line up –
  /// then only the full English sentence is shown.
  List<_Gloss>? _glossFor(_Line line) {
    final tokens =
        line.arabic.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2) return null;

    List<_Gloss> prefixThenNoun(List<String> before, String noun) {
      if (tokens.length <= before.length) return const [];
      return [
        for (var i = 0; i < before.length; i++) _Gloss(tokens[i], before[i]),
        _Gloss(tokens.sublist(before.length).join(' '), noun),
      ];
    }

    const verbs = {
      'eat': 'eat',
      'drink': 'drink',
      'ride': 'ride',
      'wear': 'wear',
      'open': 'open',
      'use': 'use',
      'see': 'see',
      'like': 'like',
    };
    const adjectives = {'big', 'small', 'beautiful', 'delicious'};

    final t = line.template;
    List<_Gloss> out;
    if (t == 'this_is') {
      out = prefixThenNoun(['this is'], _indef);
    } else if (t == 'have') {
      out = prefixThenNoun(['I have'], _indef);
    } else if (t == 'where') {
      out = prefixThenNoun(['where $_be'], '$_def?');
    } else if (verbs.containsKey(t)) {
      out = prefixThenNoun(['I', verbs[t]!], _def);
    } else if (t == 'play') {
      out = prefixThenNoun(['I', 'play'], 'with $_def');
    } else if (t == 'sit' || t == 'sleep') {
      out = prefixThenNoun(['I', t, 'on'], _def);
    } else if (t == 'open_with') {
      out = prefixThenNoun(['I', 'open', 'the door'], 'with $_def');
    } else if (adjectives.contains(t)) {
      // الْبَابُ كَبِيرٌ → noun first, adjective last
      out = [
        _Gloss(tokens.sublist(0, tokens.length - 1).join(' '), _def),
        _Gloss(tokens.last, '$_be $t'),
      ];
    } else {
      return null;
    }
    return out.isEmpty ? null : out;
  }

  // ---------- audio ----------

  String _sentenceAsset(_Line l) {
    if (l.audio.isEmpty) return '';
    return l.audio.contains('/') ? l.audio : 'sentences/${l.audio}';
  }

  /// Waits until the current clip ends (polls `playing`, max ~12 s).
  Future<void> _waitQuiet(int run) async {
    await Future.delayed(const Duration(milliseconds: 250));
    for (var i = 0; i < 60; i++) {
      if (!mounted || run != _run) return;
      if (!_audio.playing.value) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _playSentence({bool intro = false}) async {
    if (_lines.isEmpty || _finished) return;
    final run = ++_run;
    _audio.stop();
    final line = _lines[_index];
    await _audio.playOrSay(
      asset: _sentenceAsset(line),
      text: line.audioText, // never `arabic` for speech
      voice: TtsVoice.lesson,
    );
    if (intro && _index == 0) {
      // first time only: "Your turn!" so the child knows to repeat
      await _waitQuiet(run);
      if (!mounted || run != _run) return;
      await _audio.playAsset('juju/juju_en_your_turn.mp3');
    }
  }

  Future<void> _playWord() async {
    _run++;
    _audio.stop();
    await _audio.playOrSay(
      asset: 'words/${_word['word_audio'] ?? '${_wordId}_word.mp3'}',
      text: '${_word['arabic_word'] ?? ''}',
      voice: TtsVoice.lessonWord,
    );
  }

  // ---------- actions ----------

  Future<void> _saidIt() async {
    if (_busy || _finished) return;
    _busy = true;
    _progress.addStars(1);

    if (_index < _lines.length - 1) {
      setState(() => _index++);
      _busy = false;
      _playSentence();
      return;
    }

    // last sentence → into the gallery
    final id = _wordId;
    if (id != null) _progress.addToGallery(id);
    _progress.addStars(2);
    setState(() => _finished = true);
    _run++;
    _audio.stop();
    await _audio.playAsset('juju/juju_en_lesson_done.mp3');
    _busy = false;
  }

  void _back() {
    if (_index > 0 && !_finished) {
      setState(() => _index--);
      _playSentence();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _openGallery() {
    _audio.stop();
    Navigator.pushNamedAndRemoveUntil(
      context,
      Routes.gallery,
      (r) => r.settings.name == Routes.huntHub || r.isFirst,
      arguments: _wordId,
    );
  }

  void _huntAgain() {
    _audio.stop();
    Navigator.pushNamedAndRemoveUntil(
      context,
      Routes.camera,
      (r) => r.settings.name == Routes.huntHub || r.isFirst,
    );
  }

  @override
  void dispose() {
    _run++;
    _audio.stop();
    super.dispose();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _lines.isEmpty
            ? _missing()
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: _finished ? _done() : _sentencePage(),
              ),
      ),
    );
  }

  Widget _missing() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Juju(pose: JujuPose.confused, size: 160),
            const SizedBox(height: 16),
            Text('Oops! Juju lost the sentences.',
                textAlign: TextAlign.center,
                style: AppTheme.english(size: 22, weight: FontWeight.w800)),
            const SizedBox(height: 20),
            BigButton(
              label: 'Back',
              icon: Icons.arrow_back_rounded,
              style: BigButtonStyle.white,
              onTap: () => Navigator.maybePop(context),
            ),
          ]),
        ),
      );

  Widget _topBar() {
    return Row(children: [
      _roundIcon(Icons.arrow_back_rounded, _back, 'Back'),
      const SizedBox(width: 12),
      Expanded(child: _dots()),
      ListenableBuilder(
        listenable: _progress,
        builder: (_, __) => Row(children: [
          Icon(Icons.star_rounded, color: AppColors.accent, size: 28),
          const SizedBox(width: 2),
          Text('${_progress.stars}',
              style: AppTheme.english(size: 20, weight: FontWeight.w800)),
        ]),
      ),
    ]);
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap, String label) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppTheme.minTap.toDouble(),
          height: AppTheme.minTap.toDouble(),
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppColors.line, offset: const Offset(0, 4))
            ],
          ),
          child: Icon(icon, color: AppColors.ink, size: 28),
        ),
      ),
    );
  }

  Widget _dots() {
    return Semantics(
      label: 'Sentence ${_index + 1} of ${_lines.length}',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _lines.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 28 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: i < _index
                    ? AppColors.good
                    : i == _index
                        ? AppColors.accent
                        : AppColors.line,
                borderRadius: BorderRadius.circular(999),
                border: i == _index
                    ? Border.all(color: AppColors.accentShadow, width: 2)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _wordRow() {
    final phon = '${_word['phonetic'] ?? ''}';
    final en = '${_word['english_word'] ?? ''}';
    return InkWell(
      onTap: _playWord,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: AppColors.line, offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Image.asset(_stickerPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                    child: Text('⭐', style: TextStyle(fontSize: 30)))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your word',
                  style: AppTheme.english(size: 13, color: AppColors.muted)),
              Text('$phon · $en',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.english(size: 17, weight: FontWeight.w800)),
            ]),
          ),
          Text('${_word['arabic_word'] ?? ''}',
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(size: 30, weight: FontWeight.w700)),
          const SizedBox(width: 6),
          Icon(Icons.volume_up_rounded, color: AppColors.blue),
        ]),
      ),
    );
  }

  Widget _sentencePage() {
    final line = _lines[_index];
    final gloss = _glossFor(line);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topBar(),
        const SizedBox(height: 12),
        _wordRow(),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Juju: talking while audio plays, listening (your turn) otherwise
                ValueListenableBuilder<bool>(
                  valueListenable: _audio.playing,
                  builder: (_, playing, __) => Center(
                    child: Juju(
                      pose: playing ? JujuPose.talking : JujuPose.listening,
                      size: 120,
                      motion: playing ? JujuMotion.bounce : JujuMotion.none,
                      onTap: _playSentence,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _sentenceCard(line, gloss)
                    .animate(key: ValueKey(_index))
                    .fadeIn(duration: 250.ms)
                    .slideX(begin: -0.08, end: 0, duration: 250.ms),
                const SizedBox(height: 12),
                ParentTip(
                  text:
                      'Play "Where is…?" – say the last sentence and let your child run and point to the object. Then swap: your child asks, you point!',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: BigButton(
              label: 'Listen',
              icon: Icons.volume_up_rounded,
              style: BigButtonStyle.accent,
              expand: true,
              onTap: _playSentence,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BigButton(
              label: 'I said it!',
              icon: Icons.star_rounded,
              style: BigButtonStyle.good,
              expand: true,
              onTap: _saidIt,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _sentenceCard(_Line line, List<_Gloss>? gloss) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius.toDouble()),
        boxShadow: [
          BoxShadow(color: AppColors.line, offset: const Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Text('Sentence ${_index + 1} of ${_lines.length}',
            style: AppTheme.english(
                size: 15, color: AppColors.muted, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (gloss != null)
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 10,
              children: [
                for (final g in gloss)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(g.arabic,
                          textDirection: TextDirection.rtl,
                          style: AppTheme.arabic(
                              size: 34, weight: FontWeight.w700)),
                      Text(g.english,
                          textDirection: TextDirection.ltr,
                          style: AppTheme.english(
                              size: 14,
                              color: AppColors.blue,
                              weight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
          )
        else
          Text(line.arabic,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(size: 36, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(line.phonetic,
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 18, weight: FontWeight.w800)),
        Text(line.english,
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 16, color: AppColors.muted)),
        const SizedBox(height: 6),
        Text('← Arabic reads right to left',
            style: AppTheme.english(size: 13, color: AppColors.muted)),
      ]),
    );
  }

  Widget _done() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ListenableBuilder(
            listenable: _progress,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.star_rounded, color: AppColors.accent, size: 28),
              Text('${_progress.stars}',
                  style: AppTheme.english(size: 20, weight: FontWeight.w800)),
            ]),
          ),
        ),
        const Spacer(),
        Juju(pose: JujuPose.rewardStar, size: 200, motion: JujuMotion.pop),
        const SizedBox(height: 12),
        Text('You said all ${_lines.length} sentences!',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 26, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
            'Your ${_englishWord.isEmpty ? 'word' : _englishWord} is in My Arabic Room ⭐',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 17, color: AppColors.muted)),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 110,
            height: 110,
            child: Image.asset(_stickerPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
        ),
        const Spacer(),
        BigButton(
          label: 'My Arabic Room',
          emoji: '🏠',
          style: BigButtonStyle.good,
          expand: true,
          onTap: _openGallery,
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'Find another!',
          emoji: '📷',
          style: BigButtonStyle.white,
          expand: true,
          onTap: _huntAgain,
        ),
      ],
    );
  }
}
