// Screen 9 · Found it  –  lib/screens/found_screen.dart
//
// Shows the word the child found: sticker in its gender frame, the word with
// full marks and the red letter, the colour sentence ("الْبَاب بُنِّيّ" –
// Your door is brown!), Listen + hold-to-talk "Say it!" (Muse Voice
// Transcribe), Juju listening. Next → Screen 10 (Make it yours).
//
// Arguments (from Screen 8): FoundArgs, or a HuntWord, or a word id String,
// or a Map {'wordId', 'colour', 'vision'}. No argument → "door" (build order).
// The recording is deleted straight after the check – never stored.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../data/audio_index.dart';
import '../services/audio.dart';
import '../services/meta_voice.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/word_card.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';

/// What Screen 8 hands to Screen 9 (and Screen 9 passes on to Screen 10).
class FoundArgs {
  final String wordId;
  final String? colourId; // colour id from MetaVision (e.g. "brown"), optional
  final bool seenByVision; // true = Muse Spark identified it from the photo

  const FoundArgs(
      {required this.wordId, this.colourId, this.seenByVision = false});

  static FoundArgs from(Object? a) {
    if (a is FoundArgs) return a;
    if (a is HuntWord) return FoundArgs(wordId: a.id);
    if (a is String && a.isNotEmpty) return FoundArgs(wordId: a);
    if (a is Map) {
      return FoundArgs(
        wordId: (a['wordId'] ?? a['id'] ?? 'door').toString(),
        colourId: a['colour']?.toString(),
        seenByVision: a['vision'] == true,
      );
    }
    return const FoundArgs(wordId: 'door');
  }
}

enum _Say { idle, recording, checking, saidIt, greatTrying, tryAgain }

class FoundScreen extends StatefulWidget {
  const FoundScreen({super.key});

  @override
  State<FoundScreen> createState() => _FoundScreenState();
}

class _FoundScreenState extends State<FoundScreen> {
  // Swatch colours for the colour row (ids match assets/data/colours.json).
  static const _swatch = <String, Color>{
    'red': Color(0xFFE53935),
    'blue': Color(0xFF1E88E5),
    'green': Color(0xFF43A047),
    'yellow': Color(0xFFFDD835),
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF212121),
    'brown': Color(0xFF8B5A2B),
    'orange': Color(0xFFFB8C00),
    'pink': Color(0xFFF48FB1),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
  };

  static const _maxTries = 2;
  static const _minHold = Duration(milliseconds: 600);
  static const _maxHold = Duration(seconds: 5);

  late FoundArgs _args;
  late HuntWord _word;
  ArabicColour? _colour;
  bool _ready = false;

  final AudioRecorder _rec = AudioRecorder();
  _Say _say = _Say.idle;
  int _tries = 0;
  bool _holding = false;
  bool _rewarded = false;
  DateTime? _recStart;
  Timer? _maxTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _args = FoundArgs.from(ModalRoute.of(context)?.settings.arguments);
    final repo = Repository.instance;
    _word = repo.huntWord(_args.wordId) ?? repo.huntWord('door')!;
    if (_args.colourId != null) _colour = repo.colour(_args.colourId!);
    _ready = true;

    // Side effects after the first frame (calling notifiers during build crashes).
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
  }

  Future<void> _intro() async {
    if (!mounted) return;
    ProgressService.instance.markFound(_word.id);
    await _playWord();
    if (!mounted) return;
    await AudioService.instance.playOrSay(
      asset: 'juju/juju_en_your_turn.mp3',
      text: 'Your turn! Hold the green button and say it.',
      voice: TtsVoice.jujuEnglish,
    );
  }

  @override
  void dispose() {
    _maxTimer?.cancel();
    _rec.dispose();
    AudioService.instance.stop();
    super.dispose();
  }

  // ---------- audio ----------

  Future<void> _playWord() =>
      AudioIndex.instance.playWord(_word.arabicWord, sticker: _word.sticker);

  /// "الْبَاب بُنِّيّ" – definite noun + colour in the word's gender (pausal, from data).
  String? get _colourSentence {
    final c = _colour;
    if (c == null) return null;
    final (ar, _) = c.forGender(_word.gender);
    return '${_word.definite} $ar';
  }

  Future<void> _playColourSentence() async {
    final s = _colourSentence;
    if (s == null) return;
    await AudioService.instance
        .say(ArabicForms.forSpeech(s), voice: TtsVoice.lesson);
  }

  Future<void> _juju(String text, {String? asset}) => asset == null
      ? AudioService.instance.say(text, voice: TtsVoice.jujuEnglish)
      : AudioService.instance
          .playOrSay(asset: asset, text: text, voice: TtsVoice.jujuEnglish);

  // ---------- say it (hold to talk) ----------

  bool get _busy => _say == _Say.recording || _say == _Say.checking;
  bool get _sayDone => _say == _Say.saidIt || _say == _Say.greatTrying;

  Future<void> _startRec() async {
    if (_busy) return;
    await AudioService.instance.stop();
    if (!await _rec.hasPermission()) {
      _juju('Ask a grown-up to let me use the microphone.');
      return;
    }
    // Finger already lifted while the permission dialog was open → don't record.
    if (!_holding || !mounted) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/say_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _rec.start(
      const RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _recStart = DateTime.now();
    if (!mounted) return;
    setState(() => _say = _Say.recording);
    _maxTimer = Timer(_maxHold, _stopRec);
  }

  Future<void> _stopRec() async {
    _maxTimer?.cancel();
    if (_say != _Say.recording) return;
    final path = await _rec.stop();
    final held = DateTime.now().difference(_recStart ?? DateTime.now());
    final file = path == null ? null : File(path);

    if (file == null || held < _minHold) {
      await _deleteQuietly(file);
      if (!mounted) return;
      setState(() => _say = _Say.idle);
      _juju('Keep holding the button while you talk!');
      return;
    }

    setState(() => _say = _Say.checking);
    final bytes = await file.readAsBytes();
    await _deleteQuietly(file); // never stored

    final result = await MetaVoice.instance.check(
      bytes,
      target: _word.arabicWord,
      variants: [_word.definite],
    );
    if (!mounted) return;
    _tries++;

    if (result.matched == true) {
      _finish(_Say.saidIt);
      await _juju('Wonderful! You said it!');
    } else if (result.matched == false && _tries < _maxTries) {
      setState(() => _say = _Say.tryAgain);
      await _juju('Nice try! Listen once more, then say it again.');
      if (mounted) await _playWord();
    } else {
      // Couldn't check (null) or second try → praise and move on.
      _finish(_Say.greatTrying);
      await _juju('Great trying!', asset: 'juju/juju_en_great_trying.mp3');
    }
  }

  void _finish(_Say s) {
    setState(() => _say = s);
    if (_rewarded) return;
    _rewarded = true;
    ProgressService.instance.addStars(s == _Say.saidIt ? 2 : 1);
  }

  Future<void> _deleteQuietly(File? f) async {
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------- navigation ----------

  void _back() {
    AudioService.instance.stop();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(Routes.camera);
    }
  }

  void _next() {
    AudioService.instance.stop();
    Navigator.pushNamed(context, Routes.customise, arguments: _args);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_args.seenByVision) _sawItLabel(),
                      WordCard(
                        sticker: _word.sticker,
                        arabic: _word.arabicWord,
                        isFeminine: _word.isFeminine,
                        english: _word.englishWord,
                        phonetic: _word.phonetic,
                        highlightLetter: _word.letter,
                        onListen: _playWord,
                      ).animate().scale(
                            begin: const Offset(0.85, 0.85),
                            duration: 450.ms,
                            curve: Curves.elasticOut,
                          ),
                      if (_colourSentence != null) ...[
                        const SizedBox(height: 12),
                        _colourRow(),
                      ],
                      const SizedBox(height: 14),
                      _jujuPanel(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BigButton(
                      label: 'Listen',
                      icon: Icons.volume_up_rounded,
                      style: BigButtonStyle.accent,
                      height: 74,
                      onTap: _playWord,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _holdMic()),
                ],
              ),
              const SizedBox(height: 12),
              _nextButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Semantics(
          label: 'Back to camera',
          button: true,
          child: InkResponse(
            onTap: _back,
            radius: 32,
            child: Container(
              width: AppTheme.minTap,
              height: AppTheme.minTap,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 2))
                ],
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 28),
            ),
          ),
        ),
        Expanded(
          child: Text(
            'You found it! 🎉',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 22, weight: FontWeight.w800),
          ),
        ),
        ListenableBuilder(
          listenable: ProgressService.instance,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: AppColors.line, offset: Offset(0, 2))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.accent, size: 24),
                const SizedBox(width: 4),
                Text('${ProgressService.instance.stars}',
                    style: AppTheme.english(size: 18, weight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sawItLabel() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text('✨ Muse Spark saw it',
              style: AppTheme.english(
                  size: 13, color: AppColors.muted, weight: FontWeight.w700)),
        ),
      );

  Widget _colourRow() {
    final c = _colour!;
    final swatch = _swatch[c.id] ?? AppColors.muted;
    return Semantics(
      label: 'Listen to the colour sentence',
      button: true,
      child: InkWell(
        onTap: _playColourSentence,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ArabicText(_colourSentence!, size: 26),
                    Text(
                      'Your ${_word.englishWord.toLowerCase()} is ${c.en}!',
                      style: AppTheme.english(
                          size: 14,
                          color: AppColors.muted,
                          weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up_rounded, color: AppColors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jujuPanel() {
    final (JujuPose pose, JujuMotion motion, String title) = switch (_say) {
      _Say.idle => (JujuPose.listening, JujuMotion.none, 'Your turn! 👂'),
      _Say.recording => (
          JujuPose.listening,
          JujuMotion.wiggle,
          "I'm listening… 👂"
        ),
      _Say.checking => (JujuPose.thinking, JujuMotion.none, 'Let me think…'),
      _Say.saidIt => (JujuPose.happy, JujuMotion.bounce, 'You said it! ⭐'),
      _Say.greatTrying => (
          JujuPose.happy,
          JujuMotion.bounce,
          'Great trying! ⭐'
        ),
      _Say.tryAgain => (
          JujuPose.encourage,
          JujuMotion.pop,
          'Nice try! Once more 💪'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE2F5EC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF9FD6BC), width: 2),
      ),
      child: Row(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AudioService.instance.playing,
            builder: (_, talking, __) => Juju(
              key: ValueKey('$pose-$motion'),
              pose: (talking && _say == _Say.idle) ? JujuPose.talking : pose,
              size: 84,
              motion: motion,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.english(
                        size: 18,
                        color: AppColors.goodShadow,
                        weight: FontWeight.w800)),
                if (!_sayDone)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text('Hold the button and say',
                          style: AppTheme.english(
                              size: 14, weight: FontWeight.w600)),
                      ArabicText(_word.arabicWord, size: 22),
                    ],
                  ),
                if (_say == _Say.checking)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(
                      color: AppColors.good,
                      backgroundColor: AppColors.line,
                      minHeight: 6,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Press and hold to record; release to check. Max 5 s, min 0.6 s.
  Widget _holdMic() {
    final rec = _say == _Say.recording;
    final disabled = _say == _Say.checking;
    return Semantics(
      label: 'Hold and say the word',
      button: true,
      child: Listener(
        onPointerDown: disabled
            ? null
            : (_) {
                _holding = true;
                _startRec();
              },
        onPointerUp: (_) {
          _holding = false;
          _stopRec();
        },
        onPointerCancel: (_) {
          _holding = false;
          _stopRec();
        },
        child: AnimatedScale(
          scale: rec ? 1.06 : 1.0,
          duration: 150.ms,
          child: Container(
            height: 74,
            decoration: BoxDecoration(
              color: disabled ? AppColors.line : AppColors.good,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: disabled ? AppColors.muted : AppColors.goodShadow,
                  offset: Offset(0, rec ? 2 : 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(rec ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                    color: Colors.white, size: 30),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    child: Text(rec ? 'Talk now!' : 'Say it!',
                        style: AppTheme.english(
                            size: 21,
                            color: Colors.white,
                            weight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Small link until the child has had a go, then a big green button.
  Widget _nextButton() {
    if (_sayDone) {
      return BigButton(
        label: 'Next: make it yours',
        emoji: '🎨',
        style: BigButtonStyle.good,
        expand: true,
        onTap: _next,
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.3);
    }
    return TextButton(
      onPressed: _busy ? null : _next,
      style: TextButton.styleFrom(minimumSize: const Size(0, AppTheme.minTap)),
      child: Text('Next: make it yours →',
          style: AppTheme.english(
              size: 17, color: AppColors.blue, weight: FontWeight.w800)),
    );
  }
}
