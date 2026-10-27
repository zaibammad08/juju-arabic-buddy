// Screen 8 – Camera
// Live preview in a yellow frame → tap "Snap!" → 3-2-1 countdown (Juju: "Hold still!")
// → photo → Muse Spark vision (MetaVision) → Screen 9 (Found it).
// Other flows: blurry / too dark / nothing found / unknown object / several objects (choice)
// / low confidence ("Is this a door?") / wrong letter (only when a target letter was given)
// / offline (Juju's camera is resting → pick from this letter's words).
//
// Photos are NEVER saved: the file is deleted right after it is read into memory.
//
// Route arguments (optional): a target letter String, e.g. 'ب', when opened from
// the My Letter hub ("Find a ب at home!"). From the Treasure Hunt hub: no arguments.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/meta_vision.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';

/// What Screen 9 receives: `ModalRoute.of(context)!.settings.arguments as FoundArgs`.
class FoundArgs {
  final HuntWord word;
  final String? colour; // colour id from vision (red, blue…) or null
  const FoundArgs(this.word, {this.colour});
}

enum _Phase { starting, noCamera, ready, counting, thinking, message }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cam;
  _Phase _phase = _Phase.starting;
  int _count = 3;
  String _bubble = 'Point at something!';
  JujuPose _pose = JujuPose.camera;
  String? _targetLetter; // only set when opened from a letter lesson
  bool _argsRead = false;
  bool _busy = false;

  Repository get _repo => Repository.instance;

  /// Letter to prefer when several objects are seen.
  String get _preferLetter =>
      _targetLetter ?? ProgressService.instance.currentLetter;

  // ───────────────────────── lifecycle ─────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsRead) {
      _argsRead = true;
      final a = ModalRoute.of(context)?.settings.arguments;
      if (a is String && a.isNotEmpty) _targetLetter = a;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _juju('cam_ready', "Point the camera at something and tap Snap!");
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (c != null) {
        _cam = null;
        c.dispose();
      }
    } else if (state == AppLifecycleState.resumed && _cam == null) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioService.instance.stop();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (mounted) setState(() => _phase = _Phase.starting);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // medium ≈ 720 px on the long side – the size the vision model needs (~768 px).
      final c = CameraController(back, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _phase = _Phase.ready;
      });
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) setState(() => _phase = _Phase.noCamera);
    }
  }

  // ───────────────────────── Juju talking ─────────────────────────

  /// Plays a line from juju_lines.json; if it isn't there yet, Juju says the
  /// English fallback with live TTS. The bubble shows the English text.
  Future<void> _juju(String id, String fallback, {JujuPose? pose}) async {
    final line = _repo.jujuLine(id);
    final en = line?['english'];
    final String text = (en is String && en.isNotEmpty) ? en : fallback;
    if (mounted) {
      setState(() {
        _bubble = text;
        if (pose != null) _pose = pose;
      });
    }
    AudioService.instance.stop();
    if (line != null) {
      await AudioService.instance.playLine(line, wait: true);
    } else {
      await AudioService.instance.say(fallback, voice: TtsVoice.jujuEnglish);
    }
  }

  void _sayWord(HuntWord w) {
    final entry = _repo.bankEntry(w.id);
    final String? asset = entry?.wordAudio;
    AudioService.instance.playOrSay(
      asset: (asset != null && asset.isNotEmpty) ? asset : null,
      text: w.arabicWord,
      voice: TtsVoice.lessonWord,
    );
  }

  // ───────────────────────── snap → check ─────────────────────────

  Future<void> _snap() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy) return;
    _busy = true;

    // 3-2-1 countdown
    setState(() {
      _phase = _Phase.counting;
      _pose = JujuPose.camera;
      _bubble = 'Hold still!';
    });
    _juju('cam_hold', 'Hold still!');
    for (var n = 3; n >= 1; n--) {
      if (!mounted) return;
      setState(() => _count = n);
      final cnt =
          _repo.jujuLine('count_$n'); // Arabic ثَلَاثَة / اثْنَان / وَاحِد
      if (cnt != null) AudioService.instance.playLine(cnt);
      await Future.delayed(const Duration(milliseconds: 900));
    }
    if (!mounted || _cam != c) {
      _busy = false;
      return;
    }

    // capture → bytes in memory → delete the file at once
    Uint8List? bytes;
    try {
      final shot = await c.takePicture();
      bytes = await shot.readAsBytes();
      try {
        await File(shot.path).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('takePicture failed: $e');
    }
    if (!mounted) return;
    if (bytes == null) {
      _busy = false;
      setState(() => _phase = _Phase.message);
      await _juju('cam_wobbly', "Oops! Let's try that again.",
          pose: JujuPose.encourage);
      return;
    }

    setState(() {
      _phase = _Phase.thinking;
      _pose = JujuPose.thinking;
      _bubble = 'Hmm… let me look!';
    });
    _juju('cam_thinking', 'Hmm, let me look!', pose: JujuPose.thinking);

    final result = await MetaVision.instance.identify(bytes);
    bytes = null; // drop the photo from memory too
    if (!mounted) return;
    _busy = false;
    await _handle(result);
  }

  Future<void> _handle(VisionResult r) async {
    final status =
        r.status.name; // ok | blurry | tooDark | nothingFound | offline
    setState(() => _phase = _Phase.message);

    switch (status) {
      case 'blurry':
        return _juju('cam_blurry', 'Too wobbly! Hold still and try again.',
            pose: JujuPose.encourage);
      case 'tooDark':
        return _juju('cam_dark', "It's too dark! Find a brighter spot.",
            pose: JujuPose.encourage);
      case 'nothingFound':
        return _juju(
            'cam_nothing', "I can't see anything yet. Try getting closer!",
            pose: JujuPose.confused);
      case 'offline':
        return _offlineChoice();
    }

    // status ok: keep only objects that are in our 65 hunt words
    final known = <({HuntWord word, String confidence})>[];
    String? newName;
    for (final o in r.objects) {
      if (o.id == 'new') {
        newName ??= o.name;
        continue;
      }
      final w = _repo.huntWord(o.id);
      if (w != null) known.add((word: w, confidence: o.confidence));
    }

    if (known.isEmpty) {
      if (newName != null) {
        // Unknown-object flow (Muse Spark word + Muse Image sticker) comes later.
        return _juju('cam_new',
            'Ooh, a $newName! That one is new for me. Let\'s find something else!',
            pose: JujuPose.thinking);
      }
      return _juju(
          'cam_nothing', "I can't see anything yet. Try getting closer!",
          pose: JujuPose.confused);
    }

    // prefer today's letter, then one object, else let the child choose
    final match = known
        .where((k) =>
            Repository.baseLetter(k.word.letter) ==
            Repository.baseLetter(_preferLetter))
        .toList();
    ({HuntWord word, String confidence}) chosen;
    if (match.isNotEmpty) {
      chosen = match.first;
    } else if (known.length == 1) {
      chosen = known.first;
    } else {
      final picked = await _chooseSheet(
        known.map((k) => k.word).toList(),
        title: 'I see a few things! Which one?',
      );
      if (picked == null) {
        _retry();
        return;
      }
      return _wrongLetterOrGo(picked, r.colour);
    }

    if (chosen.confidence == 'low') {
      final yes = await _confirmSheet(chosen.word);
      if (yes != true) {
        _retry();
        return;
      }
    }
    return _wrongLetterOrGo(chosen.word, r.colour);
  }

  /// Only when hunting for a specific letter: gentle note, child may still learn it.
  Future<void> _wrongLetterOrGo(HuntWord w, String? colour) async {
    final t = _targetLetter;
    if (t != null &&
        Repository.baseLetter(w.letter) != Repository.baseLetter(t)) {
      _sayWord(w);
      final learn = await _wrongLetterSheet(w, t);
      if (learn != true) {
        _retry();
        return;
      }
    }
    _goFound(w, colour);
  }

  Future<void> _offlineChoice() async {
    _juju('cam_offline', "My camera is resting. Which one did you find?",
        pose: JujuPose.sleepy);
    var words = _repo.huntWordsForLetter(_preferLetter).toList();
    if (words.isEmpty) words = List.of(_repo.huntWords);
    words.shuffle(Random());
    final picked = await _chooseSheet(words.take(4).toList(),
        title: 'My camera is resting. Which one did you find?');
    if (picked == null) {
      _retry();
      return;
    }
    _goFound(picked, null);
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ready;
      _pose = JujuPose.camera;
    });
    _juju('cam_again', "Let's try again! Point and tap Snap.");
  }

  void _goFound(HuntWord w, String? colour) {
    AudioService.instance.stop();
    final c = (colour == null || colour == 'unclear') ? null : colour;
    Navigator.pushReplacementNamed(context, Routes.found,
        arguments: FoundArgs(w, colour: c));
  }

  // ───────────────────────── sheets ─────────────────────────

  Future<HuntWord?> _chooseSheet(List<HuntWord> words,
      {required String title}) {
    return showModalBottomSheet<HuntWord>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTheme.english(
                      size: 20, color: AppColors.ink, weight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final w in words)
                    _ChoiceTile(
                      word: w,
                      onTap: () {
                        _sayWord(w);
                        Navigator.pop(ctx, w);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Take another photo',
                    style: AppTheme.english(
                        size: 16,
                        color: AppColors.blue,
                        weight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmSheet(HuntWord w) {
    AudioService.instance.say('Is this a ${w.englishWord.toLowerCase()}?',
        voice: TtsVoice.jujuEnglish);
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Sticker(word: w, size: 120),
              const SizedBox(height: 8),
              Text('Is this a ${w.englishWord.toLowerCase()}?',
                  style: AppTheme.english(
                      size: 22, color: AppColors.ink, weight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: BigButton(
                      label: 'No',
                      emoji: '🤔',
                      style: BigButtonStyle.white,
                      height: 72,
                      expand: true,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BigButton(
                      label: 'Yes!',
                      emoji: '✓',
                      style: BigButtonStyle.good,
                      height: 72,
                      expand: true,
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _wrongLetterSheet(HuntWord w, String target) {
    AudioService.instance.say(
        "That's a ${w.englishWord.toLowerCase()}! Can you find something with $target?",
        voice: TtsVoice.jujuEnglish);
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Sticker(word: w, size: 110),
              ArabicText(w.arabicWord,
                  size: 40, highlightLetter: w.letter, firstOnly: true),
              Text(
                'This starts with ${w.letter}. Can you find something with $target?',
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 18, color: AppColors.ink, weight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: 'Find a $target',
                emoji: '📷',
                style: BigButtonStyle.good,
                height: 72,
                expand: true,
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: 10),
              BigButton(
                label: 'Learn this word',
                emoji: '📖',
                style: BigButtonStyle.white,
                height: 64,
                expand: true,
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              // top bar
              Row(
                children: [
                  _RoundBack(onTap: () {
                    AudioService.instance.stop();
                    Navigator.maybePop(context);
                  }),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _targetLetter == null
                          ? 'Treasure Hunt'
                          : 'Find a $_targetLetter!',
                      style: AppTheme.english(
                          size: 22,
                          color: AppColors.ink,
                          weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // preview in yellow frame
              Expanded(child: _previewFrame()),
              const SizedBox(height: 10),

              // Juju + bubble
              Row(
                children: [
                  ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        AppColors.bg, BlendMode.multiply),
                    child:
                        Juju(pose: _pose, size: 84, motion: JujuMotion.bounce),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SpeechBubble(
                      tailOnLeft: true,
                      child: Text(_bubble,
                          style: AppTheme.english(
                              size: 17,
                              color: AppColors.ink,
                              weight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // main action
              _mainButton(),
              const SizedBox(height: 8),
              Text(
                '🔒 Photos are checked, then deleted. Never saved.',
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 13, color: AppColors.muted, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainButton() {
    switch (_phase) {
      case _Phase.noCamera:
        return BigButton(
            label: 'Try again',
            emoji: '🔄',
            style: BigButtonStyle.good,
            height: 80,
            expand: true,
            onTap: _initCamera);
      case _Phase.message:
        return BigButton(
            label: 'Snap again!',
            emoji: '📷',
            style: BigButtonStyle.good,
            height: 80,
            expand: true,
            onTap: () {
              setState(() {
                _phase = _Phase.ready;
                _pose = JujuPose.camera;
              });
              _snap();
            });
      case _Phase.ready:
        return BigButton(
            label: 'Snap!',
            emoji: '📷',
            style: BigButtonStyle.good,
            height: 80,
            expand: true,
            onTap: _snap);
      case _Phase.starting:
      case _Phase.counting:
      case _Phase.thinking:
        return Opacity(
          opacity: 0.5,
          child: BigButton(
              label: _phase == _Phase.thinking ? 'Looking…' : 'Snap!',
              emoji: '📷',
              style: BigButtonStyle.good,
              height: 80,
              expand: true,
              onTap: () {}),
        );
    }
  }

  Widget _previewFrame() {
    final c = _cam;
    Widget inner;
    if (_phase == _Phase.noCamera) {
      inner = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Juju needs the camera.\nAsk a grown-up to allow it in Settings.',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 18, color: AppColors.ink, weight: FontWeight.w700),
          ),
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      inner =
          const Center(child: CircularProgressIndicator(color: AppColors.good));
    } else {
      final ps = c.value.previewSize;
      inner = ps == null
          ? CameraPreview(c)
          : FittedBox(
              fit: BoxFit.cover,
              // previewSize is landscape; swap for portrait
              child: SizedBox(
                  width: ps.height, height: ps.width, child: CameraPreview(c)),
            );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.accent, width: 6),
        boxShadow: const [
          BoxShadow(
              color: AppColors.accentShadow,
              offset: Offset(0, 6),
              blurRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radius - 6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            inner,
            if (_phase == _Phase.counting)
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(230),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text('$_count',
                      style: AppTheme.english(
                          size: 80,
                          color: AppColors.ink,
                          weight: FontWeight.w800)),
                ),
              ),
            if (_phase == _Phase.thinking)
              Container(
                color: Colors.white.withAlpha(140),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                      color: AppColors.good, strokeWidth: 7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── small private widgets ─────────────────────────

class _RoundBack extends StatelessWidget {
  final VoidCallback onTap;
  const _RoundBack({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Container(
        width: AppTheme.minTap,
        height: AppTheme.minTap,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: AppColors.line, offset: Offset(0, 3), blurRadius: 0)
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const Icon(Icons.arrow_back_rounded,
                color: AppColors.ink, size: 30),
          ),
        ),
      ),
    );
  }
}

class _Sticker extends StatelessWidget {
  final HuntWord word;
  final double size;
  const _Sticker({required this.word, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/${word.id}.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child:
            Center(child: Text('🧸', style: TextStyle(fontSize: size * 0.5))),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final HuntWord word;
  final VoidCallback onTap;
  const _ChoiceTile({required this.word, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final frame = word.isFeminine ? AppColors.feminine : AppColors.masculine;
    return Semantics(
      button: true,
      label: word.englishWord,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: frame, width: 3),
          boxShadow: [
            BoxShadow(
                color: frame.withAlpha(90),
                offset: const Offset(0, 5),
                blurRadius: 0)
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Sticker(word: word, size: 80),
                  ArabicText(word.arabicWord, size: 26),
                  Text(word.englishWord,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.english(
                          size: 14,
                          color: AppColors.muted,
                          weight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
