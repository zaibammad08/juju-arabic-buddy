// Screen 4 – Speak (letter_speak_screen.dart)
// Step 1: short vowels with movement (fatha hands up, kasra hands down, damma round lips)
// Step 2: long vowels (short → long, e.g. بَ … بَا)
// Step 3: this week's sentence ×3 with the speaking check (Muse Voice Transcribe)
// Step 4: done → markSkillDone(letter, 'speak'), +2 stars
//
// Kid rules: one main action per screen, everything spoken, never "wrong" –
// Juju takes the blame ("I was a bit sleepy"), after 2 tries we praise and move on.
// Recordings are deleted straight after the check and never stored.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../services/audio.dart';
import '../services/meta_voice.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';
import '../widgets/parent_tip.dart';

// ───────────────────────── small data holders ─────────────────────────

class _Vowel {
  final String say; // syllable with marks (display + audio)
  final String sound; // "ba", "bii" …
  final String exEmoji, exSay, exEn;
  const _Vowel({
    required this.say,
    this.sound = '',
    this.exEmoji = '',
    this.exSay = '',
    this.exEn = '',
  });
}

class _Gloss {
  final String ar; // with marks
  final String en;
  const _Gloss(this.ar, this.en);
}

class _Sentence {
  final String emoji, say, tr, en;
  final List<_Gloss> words;
  const _Sentence({
    required this.say,
    this.emoji = '',
    this.tr = '',
    this.en = '',
    this.words = const [],
  });
}

enum _Mic { idle, busy, listening, checking }

// Movement for fatha / kasra / damma (index 0 / 1 / 2)
const _moves = [
  ('🙌', 'Hands up!'),
  ('👇', 'Hands down!'),
  ('😗', 'Round lips!'),
];

class LetterSpeakScreen extends StatefulWidget {
  const LetterSpeakScreen({super.key});

  @override
  State<LetterSpeakScreen> createState() => _LetterSpeakScreenState();
}

class _LetterSpeakScreenState extends State<LetterSpeakScreen> {
  // Tuning (adjust after testing with real children's voices)
  static const double _speechDb = -32; // louder than this (dBFS) = speaking
  static const int _quietMs = 700; // stop after this much quiet
  static const int _maxSeconds = 6; // sentence max length
  static const int _preRollMs = 500; // record before the green light
  static const int _timesToSay = 3;

  bool _ready = false;
  String _letter = '';

  List<_Vowel> _short = [];
  List<_Vowel> _long = [];
  List<_Sentence> _sentences = [];
  int _sIndex = 0;

  int _step = 0; // 0 short, 1 long, 2 sentence, 3 done
  int? _active; // active vowel card
  final Set<int> _saidShort = {};
  final Set<int> _saidLong = {};

  int _attempts = 0; // finished attempts of the sentence (0..3)
  int _tries = 0; // failed tries in the current attempt
  _Mic _mic = _Mic.idle;
  JujuPose? _poseOverride;
  String _bubble = '';

  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  double _level = 0;
  bool _disposed = false;

  // ───────────────────────── setup ─────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    _letter = (arg is String && arg.isNotEmpty)
        ? arg
        : ProgressService.instance.currentLetter;
    _load();
    _ready = true;
    _bubble = 'Move with me! Tap a sound.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jujuSays('Move with me! Tap a sound, then say it.');
    });
  }

  void _load() {
    final lesson = _lessonMap(_letter);

    _short = _readVowels(lesson['vowels']);
    if (_short.length < 3) _short = _defaultShort(_letter);
    _long = _readVowels(lesson['long_vowels']);
    if (_long.length < 3) _long = _defaultLong(_letter);

    _sentences = _readSentences(lesson['speak']);
    if (_sentences.isEmpty) _sentences = _bankSentences(_letter);

    // One sentence starter per week: keep the first starter group,
    // and show one sentence per day.
    if (_sentences.isNotEmpty) {
      final first = _firstWord(_sentences.first.say);
      final group =
          _sentences.where((s) => _firstWord(s.say) == first).toList();
      if (group.isNotEmpty) _sentences = group;
      final now = DateTime.now();
      final dayOfYear = now.difference(DateTime(now.year)).inDays;
      _sIndex = dayOfYear % _sentences.length;
    }
  }

  /// Lesson data as a plain map, whatever Repository.lesson() returns.
  Map<String, dynamic> _lessonMap(String letter) {
    dynamic raw;
    try {
      raw = Repository.instance.lesson(Repository.baseLetter(letter));
    } catch (e) {
      debugPrint('Speak: no lesson for $letter: $e');
      return <String, dynamic>{};
    }
    if (raw == null) return <String, dynamic>{};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    try {
      final inner = (raw as dynamic).raw; // model class with .raw
      if (inner is Map) return Map<String, dynamic>.from(inner);
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// Lesson data as a plain map, whatever Repository.lesson() returns.

  String _s(dynamic m, String k) =>
      (m is Map && m[k] != null) ? m[k].toString() : '';

  List<_Vowel> _readVowels(dynamic list) {
    if (list is! List) return [];
    final out = <_Vowel>[];
    for (final v in list) {
      final ex = v is Map ? v['ex'] : null;
      final say = _s(v, 'say').isNotEmpty ? _s(v, 'say') : _s(v, 'ar');
      if (say.isEmpty) continue;
      out.add(_Vowel(
        say: say,
        sound: _s(v, 's'),
        exEmoji: _s(ex, 'e'),
        exSay: _s(ex, 'say'),
        exEn: _s(ex, 'en'),
      ));
    }
    return out.take(3).toList();
  }

  List<_Sentence> _readSentences(dynamic list) {
    if (list is! List) return [];
    final out = <_Sentence>[];
    for (final s in list) {
      final say = _s(s, 'say').isNotEmpty ? _s(s, 'say') : _s(s, 'ar');
      if (say.isEmpty) continue;
      final words = <_Gloss>[];
      final w = s is Map ? s['w'] : null;
      if (w is List) {
        for (final g in w) {
          if (g is List && g.length >= 3) {
            words.add(_Gloss(g[1].toString(), g[2].toString()));
          }
        }
      }
      out.add(_Sentence(
        say: say,
        emoji: _s(s, 'e'),
        tr: _s(s, 'tr'),
        en: _s(s, 'en'),
        words: words,
      ));
    }
    return out;
  }

  /// Fallback: first sentence of each hunt word for this letter (sentence bank).
  List<_Sentence> _bankSentences(String letter) {
    final out = <_Sentence>[];
    try {
      for (final w in Repository.instance.huntWordsForLetter(letter)) {
        final entry = Repository.instance.bankEntry(w.id);
        if (entry == null || entry.sentences.isEmpty) continue;
        final line = entry.sentences.first;
        out.add(_Sentence(
          say: line.arabic,
          tr: line.phonetic,
          en: line.english,
        ));
      }
    } catch (e) {
      debugPrint('Speak: bank fallback failed: $e');
    }
    return out;
  }

  // Syllables built from the letter when a lesson has no vowel lists (e.g. alif).
  static const _fatha = '\u064E', _kasra = '\u0650', _damma = '\u064F';

  List<_Vowel> _defaultShort(String l) {
    if (Repository.baseLetter(l) == 'ا') {
      return const [
        _Vowel(say: 'أَ', sound: 'a'),
        _Vowel(say: 'إِ', sound: 'i'),
        _Vowel(say: 'أُ', sound: 'u'),
      ];
    }
    return [
      _Vowel(say: '$l$_fatha'),
      _Vowel(say: '$l$_kasra'),
      _Vowel(say: '$l$_damma'),
    ];
  }

  List<_Vowel> _defaultLong(String l) {
    if (Repository.baseLetter(l) == 'ا') {
      return const [
        _Vowel(say: 'آ', sound: 'aa'),
        _Vowel(say: 'إِي', sound: 'ii'),
        _Vowel(say: 'أُو', sound: 'uu'),
      ];
    }
    return [
      _Vowel(say: '$l$_fathaا'),
      _Vowel(say: '$l$_kasraي'),
      _Vowel(say: '$l$_dammaو'),
    ];
  }

  String _firstWord(String s) => s.trim().split(RegExp(r'\s+')).first;

  /// This week's key word = the last word of the sentence (no punctuation).
  String _keyword(_Sentence s) {
    final parts = s.say.trim().split(RegExp(r'\s+'));
    return parts.last.replaceAll(RegExp(r'[.,!?؟،]'), '');
  }

  @override
  void dispose() {
    _disposed = true;
    _ampSub?.cancel();
    _rec.stop().catchError((_) => null);
    _rec.dispose();
    AudioService.instance.stop();
    super.dispose();
  }

  // ───────────────────────── audio helpers ─────────────────────────

  Future<void> _waitAudio() async {
    final p = AudioService.instance.playing;
    var n = 0;
    while (p.value && n < 150 && !_disposed) {
      await Future.delayed(const Duration(milliseconds: 100));
      n++;
    }
  }

  Future<void> _jujuSays(String english) async {
    if (_disposed) return;
    setState(() => _bubble = english);
    await AudioService.instance.say(english, voice: TtsVoice.jujuEnglish);
    await _waitAudio();
  }

  Future<void> _sayArabic(String text, {bool slow = true}) async {
    if (_disposed || text.isEmpty) return;
    await AudioService.instance.say(
      ArabicForms.forSpeech(text),
      voice: slow ? TtsVoice.lessonWord : TtsVoice.lesson,
    );
    await _waitAudio();
  }

  Future<void> _playJujuFile(String file) async {
    if (_disposed) return;
    await AudioService.instance.playAsset(file, wait: true);
    await _waitAudio();
  }

  // ───────────────────────── vowel steps ─────────────────────────

  Future<void> _tapVowel(int i) async {
    if (_mic != _Mic.idle) return;
    final long = _step == 1;
    final list = long ? _long : _short;
    if (i >= list.length) return;
    setState(() {
      _active = i;
      _mic = _Mic.busy;
    });
    final v = list[i];
    final move = _moves[i];
    if (long) {
      await _jujuSays('${move.$2} Now stretch it long!');
      if (i < _short.length) await _sayArabic(_short[i].say);
      await Future.delayed(const Duration(milliseconds: 250));
      await _sayArabic(v.say);
    } else {
      await _jujuSays(move.$2);
      await _sayArabic(v.say);
    }
    if (v.exSay.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _sayArabic(v.exSay);
    }
    if (!_disposed) {
      setState(() => _mic = _Mic.idle);
      await _jujuSays('Your turn! Do the move and say it.');
    }
  }

  Future<void> _saidVowel() async {
    final i = _active;
    if (i == null || _mic != _Mic.idle) return;
    final set = _step == 1 ? _saidLong : _saidShort;
    setState(() {
      set.add(i);
      _poseOverride = JujuPose.happy;
      _active = null;
    });
    final total = _step == 1 ? _long.length : _short.length;
    if (set.length >= total) {
      await _jujuSays(_step == 1
          ? 'Great stretching! Now let\'s say a sentence.'
          : 'Super moves! Now let\'s make them long.');
    } else {
      await _jujuSays('Yes! Tap the next sound.');
    }
    if (!_disposed) setState(() => _poseOverride = null);
  }

  void _nextStep() {
    AudioService.instance.stop();
    setState(() {
      _step++;
      _active = null;
      _poseOverride = null;
    });
    if (_step == 1) {
      _jujuSays('Short, then long. Tap a sound!');
    } else if (_step == 2) {
      _jujuSays('Listen to my sentence. Then say it three times!');
    }
  }

  // ───────────────────────── sentence step ─────────────────────────

  _Sentence? get _sentence =>
      _sentences.isEmpty ? null : _sentences[_sIndex % _sentences.length];

  Future<void> _listenSentence() async {
    final s = _sentence;
    if (s == null || _mic != _Mic.idle) return;
    setState(() => _mic = _Mic.busy);
    await _sayArabic(s.say, slow: false);
    if (!_disposed) setState(() => _mic = _Mic.idle);
  }

  Future<void> _tapWord(_Gloss g) async {
    if (_mic != _Mic.idle) return;
    setState(() => _bubble = g.en);
    await _sayArabic(g.ar);
  }

  void _otherSentence() {
    if (_attempts > 0 || _mic != _Mic.idle || _sentences.length < 2) return;
    setState(() {
      _sIndex = (_sIndex + 1) % _sentences.length;
      _tries = 0;
    });
    _listenSentence();
  }

  Future<void> _myTurn() async {
    final s = _sentence;
    if (s == null || _mic != _Mic.idle) return;
    setState(() {
      _mic = _Mic.busy;
      _poseOverride = null;
    });

    // 1) model sentence, 2) "your turn"
    await _sayArabic(s.say, slow: false);
    await _playJujuFile('juju/juju_en_your_turn.mp3');
    if (_disposed) return;

    // 3) record (pre-roll, green light, auto-stop)
    final bytes = await _record();
    if (_disposed) return;

    if (bytes == null) {
      // No microphone or recording failed → never block the child.
      await _countAttempt(praise: true);
      return;
    }
    if (bytes.isEmpty) {
      await _missed(); // silence
      return;
    }

    // 4) check with Muse Voice Transcribe
    setState(() {
      _mic = _Mic.checking;
      _poseOverride = JujuPose.thinking;
      _bubble = 'Hmm, let me think…';
    });
    bool? ok;
    try {
      final res = await MetaVoice.instance.check(
        bytes,
        target: s.say,
        variants: [_keyword(s)],
      );
      ok = _judge(res, s);
    } catch (e) {
      debugPrint('Speak: voice check failed: $e');
      ok = null;
    }
    if (_disposed) return;

    if (ok == false) {
      await _missed();
    } else {
      await _countAttempt(praise: true); // true or null (couldn't check)
    }
  }

  /// true = heard it, false = didn't match, null = couldn't check.
  bool? _judge(VoiceCheck res, _Sentence s) {
    if (res.matched == true) return true;
    final heard = (res.heard ?? '').trim();
    if (heard.isEmpty) return res.matched == null ? null : false;

    String clean(String w) {
      var n = ArabicForms.normalise(ArabicForms.strip(w))
          .replaceAll(RegExp(r'[.,!?؟،]'), '');
      if (n.startsWith('ال') && n.length > 3) n = n.substring(2);
      return n;
    }

    // Whole sentence close enough?
    if (ArabicForms.similarity(clean(heard), clean(s.say)) >=
        MetaVoice.threshold) {
      return true;
    }
    // Single-word rule: the week's key word is in what Juju heard.
    final key = clean(_keyword(s));
    for (final w in heard.split(RegExp(r'\s+'))) {
      final n = clean(w);
      if (n.isEmpty) continue;
      if (ArabicForms.similarity(n, key) >= MetaVoice.threshold) return true;
    }
    return res.matched == null ? null : false;
  }

  Future<void> _missed() async {
    _tries++;
    if (_tries >= 2) {
      // Praise the effort and move on.
      setState(() => _poseOverride = JujuPose.encourage);
      _bubble = 'Great trying! ⭐';
      await _playJujuFile('juju/juju_en_great_trying.mp3');
      await _countAttempt(praise: false);
      return;
    }
    setState(() => _poseOverride = JujuPose.sleepy);
    await _jujuSays(
        'Sorry, I missed it! I was a bit sleepy. Can you say it louder?');
    final s = _sentence;
    if (s != null) await _sayArabic(s.say, slow: false);
    if (!_disposed) {
      setState(() {
        _mic = _Mic.idle;
        _poseOverride = null;
      });
    }
  }

  Future<void> _countAttempt({required bool praise}) async {
    setState(() {
      _attempts++;
      _tries = 0;
      _poseOverride = JujuPose.happy;
    });
    HapticFeedback.mediumImpact();
    if (praise) {
      final left = _timesToSay - _attempts;
      await _jujuSays(left <= 0
          ? 'Well done! You said it three times!'
          : left == 1
              ? 'Well done! One more time!'
              : 'Well done! Say it again!');
    }
    if (_disposed) return;
    if (_attempts >= _timesToSay) {
      await _finish();
    } else {
      setState(() {
        _mic = _Mic.idle;
        _poseOverride = null;
      });
    }
  }

  Future<void> _finish() async {
    await ProgressService.instance.markSkillDone(_letter, 'speak');
    await ProgressService.instance.addStars(2);
    if (_disposed) return;
    setState(() {
      _step = 3;
      _mic = _Mic.idle;
      _poseOverride = null;
      _bubble = 'You did Speak! ⭐⭐';
    });
    await _playJujuFile('juju/juju_en_skill_speak_done.mp3');
  }

  // ───────────────────────── recording ─────────────────────────

  /// Returns WAV bytes, an empty list if the child stayed quiet,
  /// or null if recording isn't possible. The temp file is deleted at once.
  Future<Uint8List?> _record() async {
    String? path;
    try {
      if (!await _rec.hasPermission()) return null;
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/juju_speak_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      final done = Completer<void>();
      var heardVoice = false;
      DateTime? quietSince;
      final started = DateTime.now();

      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
        final now = DateTime.now();
        final db = a.current;
        if (!_disposed && _mic == _Mic.listening) {
          setState(() => _level = ((db + 50) / 50).clamp(0.0, 1.0));
        }
        if (db > _speechDb) {
          heardVoice = true;
          quietSince = null;
        } else if (heardVoice) {
          quietSince ??= now;
          if (now.difference(quietSince!).inMilliseconds > _quietMs &&
              !done.isCompleted) {
            done.complete();
          }
        }
        if (now.difference(started).inMilliseconds >
                (_maxSeconds * 1000 + _preRollMs) &&
            !done.isCompleted) {
          done.complete();
        }
      });

      // Pre-roll: already recording; the green light comes 0.5 s later.
      await Future.delayed(const Duration(milliseconds: _preRollMs));
      if (_disposed) {
        await _rec.stop();
        return null;
      }
      HapticFeedback.lightImpact();
      setState(() {
        _mic = _Mic.listening;
        _poseOverride = JujuPose.listening;
        _bubble = 'I\'m listening! 👂';
      });

      await done.future
          .timeout(const Duration(seconds: _maxSeconds + 2), onTimeout: () {});
      await _ampSub?.cancel();
      _ampSub = null;
      final out = await _rec.stop();
      if (!_disposed) setState(() => _level = 0);

      final file = File(out ?? path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      return heardVoice ? bytes : Uint8List(0);
    } catch (e) {
      debugPrint('Speak: recording failed: $e');
      try {
        await _ampSub?.cancel();
        _ampSub = null;
        await _rec.stop();
        if (path != null) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  // ───────────────────────── UI ─────────────────────────

  JujuPose _defaultPose() {
    if (_step == 3) return JujuPose.gradCap;
    if (_step == 2) return JujuPose.microphone;
    return JujuPose.idle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _stepDots(),
            _jujuHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: switch (_step) {
                  0 || 1 => _vowelStep(),
                  2 => _sentenceStep(),
                  _ => _doneStep(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Text('Speak  ',
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
          ArabicText(_letter, size: 30, color: AppColors.highlight),
          const Spacer(),
          ListenableBuilder(
            listenable: ProgressService.instance,
            builder: (_, __) => Text('⭐ ${ProgressService.instance.stars}',
                style: AppTheme.english(size: 20, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final on = i <= _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          width: i == _step ? 28 : 12,
          height: 12,
          decoration: BoxDecoration(
            color: on ? AppColors.good : AppColors.line,
            borderRadius: BorderRadius.circular(6),
          ),
        );
      }),
    );
  }

  Widget _jujuHeader() {
    final listening = _mic == _Mic.listening;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: listening
                      ? [
                          BoxShadow(
                            color: AppColors.good.withValues(alpha: 0.55),
                            blurRadius: 28,
                            spreadRadius: 6,
                          )
                        ]
                      : const [],
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: AudioService.instance.playing,
                  builder: (_, talking, __) => Juju(
                    pose: _poseOverride ??
                        (talking && _mic != _Mic.listening
                            ? JujuPose.talking
                            : _defaultPose()),
                    size: 120,
                    motion: listening ? JujuMotion.none : JujuMotion.bounce,
                  ),
                ),
              ),
              SizedBox(height: 26, child: listening ? _soundWave() : null),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SpeechBubble(
              tailOnLeft: true,
              child: Text(
                _bubble,
                style: AppTheme.english(size: 18, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundWave() {
    const factors = [0.5, 0.8, 1.0, 0.8, 0.5];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final f in factors)
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 6,
            height: 6 + 20 * _level * f,
            decoration: BoxDecoration(
              color: AppColors.good,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  // ── Steps 1 + 2: vowels ──
  Widget _vowelStep() {
    final long = _step == 1;
    final list = long ? _long : _short;
    final said = long ? _saidLong : _saidShort;
    final allSaid = said.length >= list.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          long ? 'Short, then LONG' : 'Short sounds – move with Juju!',
          textAlign: TextAlign.center,
          style: AppTheme.english(size: 22, weight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.rtl, // fatha card on the right
          child: Row(
            children: [
              for (var i = 0; i < list.length; i++)
                Expanded(child: _vowelCard(i, list[i], long, said.contains(i))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (allSaid)
          BigButton(
            label: long ? 'Next: my sentence' : 'Next: long sounds',
            emoji: '➜',
            style: BigButtonStyle.good,
            expand: true,
            onTap: _nextStep,
          )
        else
          BigButton(
            label: 'I said it!',
            emoji: '⭐',
            style: BigButtonStyle.accent,
            expand: true,
            onTap: (_active != null && _mic == _Mic.idle) ? _saidVowel : null,
          ),
        if (!long) ...[
          const SizedBox(height: 16),
          const ParentTip(
            title: 'Parent tip',
            text:
                'Do the moves together: hands up for fatha, hands down for kasra, '
                'round lips for damma. Say each sound short; on the next page, stretch it long.',
          ),
        ],
      ],
    );
  }

  Widget _vowelCard(int i, _Vowel v, bool long, bool done) {
    final active = _active == i;
    final move = _moves[i];
    return GestureDetector(
      onTap: () => _tapVowel(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        constraints: const BoxConstraints(minHeight: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: active
                ? AppColors.accent
                : done
                    ? AppColors.good
                    : AppColors.line,
            width: active || done ? 4 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.line,
              offset: Offset(0, AppTheme.shadowDepth.toDouble()),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(move.$1, style: const TextStyle(fontSize: 34)),
            Text(move.$2,
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 13, color: AppColors.muted, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (long && i < _short.length)
              ArabicText(
                _short[i].say,
                size: 26,
                color: AppColors.muted,
              ),
            ArabicText(
              v.say,
              size: long ? 52 : 60,
              highlightLetter: _letter,
            ),
            if (v.sound.isNotEmpty)
              Text(v.sound,
                  style: AppTheme.english(size: 16, weight: FontWeight.w700)),
            if (v.exSay.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(v.exEmoji, style: const TextStyle(fontSize: 26)),
              ArabicText(v.exSay,
                  size: 20, highlightLetter: _letter, firstOnly: true),
              if (v.exEn.isNotEmpty)
                Text(v.exEn,
                    style: AppTheme.english(size: 13, color: AppColors.muted)),
            ],
            if (done)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('⭐', style: TextStyle(fontSize: 22)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Step 3: sentence ×3 ──
  Widget _sentenceStep() {
    final s = _sentence;
    if (s == null) {
      return Column(
        children: [
          Text('No sentence for this letter yet.',
              style: AppTheme.english(size: 18)),
          const SizedBox(height: 16),
          BigButton(label: 'Finish', emoji: '⭐', onTap: _finish, expand: true),
        ],
      );
    }
    final micFree = _mic == _Mic.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('This week\'s sentence',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 22, weight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            boxShadow: [
              BoxShadow(
                color: AppColors.line,
                offset: Offset(0, AppTheme.shadowDepth.toDouble()),
              ),
            ],
          ),
          child: Column(
            children: [
              if (s.emoji.isNotEmpty)
                Text(s.emoji, style: const TextStyle(fontSize: 56)),
              ArabicText(s.say, size: 38, highlightLetter: _letter),
              if (s.words.isNotEmpty) ...[
                const SizedBox(height: 10),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final g in s.words) _wordChip(g)],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (s.en.isNotEmpty)
                Text(s.en,
                    textAlign: TextAlign.center,
                    style: AppTheme.english(size: 18, weight: FontWeight.w700)),
              if (s.tr.isNotEmpty)
                Text(s.tr,
                    textAlign: TextAlign.center,
                    style: AppTheme.english(size: 15, color: AppColors.muted)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _timesToSay,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedScale(
                      scale: i < _attempts ? 1.15 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Text(i < _attempts ? '⭐' : '☆',
                          style: TextStyle(
                              fontSize: 34,
                              color: i < _attempts ? null : AppColors.line)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: BigButton(
                label: 'Listen',
                emoji: '🔊',
                style: BigButtonStyle.white,
                onTap: micFree ? _listenSentence : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: BigButton(
                label: switch (_mic) {
                  _Mic.listening => 'Listening…',
                  _Mic.checking => 'Checking…',
                  _Mic.busy => 'Get ready…',
                  _Mic.idle => 'My turn!',
                },
                emoji: '🎤',
                style: BigButtonStyle.good,
                onTap: micFree ? _myTurn : null,
              ),
            ),
          ],
        ),
        if (_attempts == 0 && _sentences.length > 1) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: micFree ? _otherSentence : null,
              style: TextButton.styleFrom(minimumSize: const Size(64, 64)),
              child: Text('Another sentence ›',
                  style: AppTheme.english(size: 16, color: AppColors.blue)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const ParentTip(
          title: 'Parent tip',
          text:
              'Wait for Juju\'s green glow, then let your child say the whole sentence. '
              'Juju only listens for this week\'s word, so a small slip is fine. '
              'Nothing is recorded or saved.',
        ),
      ],
    );
  }

  Widget _wordChip(_Gloss g) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _tapWord(g),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArabicText(g.ar, size: 24, highlightLetter: _letter),
            Text(g.en,
                style: AppTheme.english(size: 13, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  // ── Step 4: done ──
  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text('🎉 Speak done! 🎉',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 28, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('+2 ⭐',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 22, color: AppColors.good, weight: FontWeight.w800)),
        const SizedBox(height: 24),
        BigButton(
          label: 'Back to my letter',
          emoji: '📖',
          style: BigButtonStyle.accent,
          expand: true,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
