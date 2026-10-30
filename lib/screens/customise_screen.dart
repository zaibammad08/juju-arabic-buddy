import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'found_screen.dart' show FoundArgs;
import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../services/audio.dart';
import '../services/meta_voice.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';

/// Screen 10 – "Make it yours"
/// Arguments (from Screen 9): HuntWord, a word id String, or
/// {'word': HuntWord|id, 'colour': visionColourId?}.
/// Next: Routes.story with {'word', 'wordId', 'colour', 'size', 'fun'}.
/// Skip: Routes.sentences with {'word', 'wordId'}.
enum _Step { colour, size, fun, done }

class CustomiseScreen extends StatefulWidget {
  const CustomiseScreen({super.key});

  @override
  State<CustomiseScreen> createState() => _CustomiseScreenState();
}

class _CustomiseScreenState extends State<CustomiseScreen> {
  // Colours offered as bubbles when vision gave none (bright, easy to tell apart).
  static const _kidColours = [
    'red',
    'blue',
    'green',
    'yellow',
    'pink',
    'purple',
    'orange'
  ];

  // Swatch colours for bubbles + live tint (display only, not lesson content).
  static const Map<String, Color> _swatch = {
    'red': Color(0xFFE53935),
    'blue': Color(0xFF1E88E5),
    'green': Color(0xFF43A047),
    'yellow': Color(0xFFFDD835),
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF263238),
    'brown': Color(0xFF8D6E63),
    'orange': Color(0xFFFB8C00),
    'pink': Color(0xFFF06292),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
  };

  static const Map<String, String> _funEmoji = {'happy': '😊', 'funny': '😜'};

  // English fallbacks if a juju_lines.json entry is missing.
  static const Map<String, String> _fallbackText = {
    'customise_colour': 'What colour do you want? Tap a bubble or say it!',
    'customise_listening': "I'm listening… say the colour!",
    'customise_try_tap': "Hmm, I didn't catch that. Tap the colour you like!",
    'customise_size': 'Big or small? You choose!',
    'customise_fun': 'Now make it fun! Happy or funny?',
    'customise_done': "Wow, it's all yours! Let's make your story!",
  };

  final _recorder = AudioRecorder();
  final _rng = Random();

  HuntWord? _word;
  List<ArabicColour> _options = [];
  _Step _step = _Step.colour;
  bool _editing = false; // changing one choice after finishing
  bool _listening = false;
  bool _started = false;
  bool _starGiven = false;

  String? _colour, _size, _fun;
  String? _phrase; // latest Arabic phrase (full marks, display only)
  String _bubble = '';

  bool get _fem => _word?.isFeminine ?? false;
  bool get _hasSize => _word?.sizeChoice ?? true;

  // ---------------------------------------------------------------- setup

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _readArgs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(_Step.colour));
  }

  void _readArgs() {
    final repo = Repository.instance;
    final args = ModalRoute.of(context)?.settings.arguments;
    HuntWord? w;
    String? detected;
    if (args is FoundArgs) {
      w = repo.huntWord(args.wordId);
      final c = args.colourId;
      if (c != null && c != 'unclear') detected = c;
    } else if (args is HuntWord) {
      w = args;
    } else if (args is String) {
      w = repo.huntWord(args);
    } else if (args is Map) {
      final a = args['word'] ?? args['wordId'] ?? args['id'];
      if (a is HuntWord) w = a;
      if (a is String) w = repo.huntWord(a);
      final c = args['colour'];
      if (c is String && c != 'unclear') detected = c;
    }
    _word = w ?? repo.huntWord('door'); // build-order default

    // 3 bubbles: the colour Muse Spark saw (if any) + 2 others.
    final ids = <String>[];
    if (detected != null && repo.colour(detected) != null) ids.add(detected);
    final pool = _kidColours.where((c) => !ids.contains(c)).toList()
      ..shuffle(_rng);
    ids.addAll(pool.take(3 - ids.length));
    ids.shuffle(_rng);
    _options = [
      for (final id in ids)
        if (repo.colour(id) != null) repo.colour(id)!,
    ];
  }

  @override
  void dispose() {
    _recorder.dispose();
    AudioService.instance.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- Juju

  void _juju(String id) {
    final line = Repository.instance.jujuLine(id);
    setState(() =>
        _bubble = (line?['english'] as String?) ?? _fallbackText[id] ?? '');
    if (line != null) AudioService.instance.playLine(line);
  }

  void _ask(_Step step) {
    if (!mounted) return;
    setState(() => _step = step);
    switch (step) {
      case _Step.colour:
        _juju('customise_colour');
      case _Step.size:
        _juju('customise_size');
      case _Step.fun:
        _juju('customise_fun');
      case _Step.done:
        _juju('customise_done');
        if (!_starGiven) {
          _starGiven = true;
          ProgressService.instance.addStars(1);
        }
    }
  }

  _Step _after(_Step s) {
    if (_editing) return _Step.done;
    switch (s) {
      case _Step.colour:
        return _hasSize ? _Step.size : _Step.fun;
      case _Step.size:
        return _Step.fun;
      default:
        return _Step.done;
    }
  }

  Future<void> _advance(_Step from) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final next = _after(from);
    if (next == _Step.done) _editing = false;
    _ask(next);
  }

  void _edit(_Step s) {
    AudioService.instance.stop();
    _editing = true;
    _ask(s);
  }

  // ---------------------------------------------------------------- Arabic helpers

  String _colourForm(ArabicColour c) =>
      (c.raw[_fem ? 'f' : 'm'] ?? '') as String;
  String _adjForm(Adjective a) => (a.raw[_fem ? 'f' : 'm'] ?? '') as String;
  String get _g => _fem ? 'f' : 'm';

  /// الْبَابُ أَحْمَرُ – definite noun + indefinite adjective, nominative.
  String _buildPhrase(String form, {bool diptote = false}) {
    final w = _word!;
    final noun = ArabicForms.noun(w, Case.nom, true);
    final adj = ArabicForms.adj(form, Case.nom, false, diptote: diptote);
    return '$noun $adj';
  }

  void _sayPhrase() {
    final p = _phrase;
    if (p == null) return;
    AudioService.instance.say(ArabicForms.forSpeech(ArabicForms.waqfAr(p)),
        voice: TtsVoice.lesson);
  }

  // ---------------------------------------------------------------- choices

  Future<void> _pickColour(ArabicColour c) async {
    await AudioService.instance.stop();
    setState(() {
      _colour = c.id;
      _phrase = _buildPhrase(_colourForm(c), diptote: c.diptote);
    });
    await AudioService.instance
        .playAsset('colours/colour_${c.id}_$_g.mp3', wait: true);
    _advance(_Step.colour);
  }

  Future<void> _pickAdj(_Step step, String id) async {
    final a = Repository.instance.adjective(id);
    if (a == null) return;
    await AudioService.instance.stop();
    setState(() {
      if (step == _Step.size) _size = id;
      if (step == _Step.fun) _fun = id;
      _phrase = _buildPhrase(_adjForm(a));
    });
    await AudioService.instance
        .playAsset('adjectives/adj_${id}_$_g.mp3', wait: true);
    _advance(step);
  }

  // ---------------------------------------------------------------- say the colour

  Future<void> _sayColour() async {
    if (_listening) return;
    await AudioService.instance.stop();
    if (!await _recorder.hasPermission()) {
      _juju('customise_try_tap');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/say_colour_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _juju('customise_listening');
    await Future.delayed(const Duration(milliseconds: 1600)); // let Juju finish
    if (!mounted) return;
    setState(() => _listening = true);
    ArabicColour? match;
    try {
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      await Future.delayed(const Duration(seconds: 3));
      final out = await _recorder.stop();
      final file = File(out ?? path);
      final bytes = await file.readAsBytes();
      try {
        await file.delete(); // the child's voice is never kept
      } catch (_) {}
      final forms = _options.map(_colourForm).toList();
      final res = await MetaVoice.instance.check(
        bytes,
        target: forms.first,
        variants: forms.skip(1).toList(),
      );
      match = _matchColour('${res.heard}');
    } catch (_) {
      match = null;
    }
    if (!mounted) return;
    setState(() => _listening = false);
    if (match != null) {
      _pickColour(match);
    } else {
      _juju('customise_try_tap');
    }
  }

  /// Local match of what was heard against the 3 bubbles (M/F Arabic + English).
  ArabicColour? _matchColour(String heard) {
    String clean(String s) =>
        ArabicForms.normalise(ArabicForms.strip(s.toLowerCase()));
    final h = clean(heard);
    if (h.isEmpty || h == 'null') return null;
    final parts = [h, ...h.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)];
    ArabicColour? best;
    var bestScore = 0.0;
    for (final c in _options) {
      final cands =
          [c.raw['m'], c.raw['f'], c.en].whereType<String>().map(clean);
      for (final cand in cands) {
        for (final p in parts) {
          final s = ArabicForms.similarity(p, cand);
          if (s > bestScore) {
            bestScore = s;
            best = c;
          }
        }
      }
    }
    return bestScore >= 0.7 ? best : null;
  }

  // ---------------------------------------------------------------- navigation

  void _goStory() {
    AudioService.instance.stop();
    Navigator.pushNamed(context, Routes.story, arguments: {
      'word': _word,
      'wordId': _word!.id,
      'colour': _colour,
      'size': _hasSize ? _size : null,
      'fun': _fun,
    });
  }

  void _skip() {
    AudioService.instance.stop();
    Navigator.pushReplacementNamed(context, Routes.sentences,
        arguments: {'word': _word, 'wordId': _word!.id});
  }

  // ---------------------------------------------------------------- UI

  String get _stickerPath {
    final s = _word?.sticker ?? '';
    if (s.isEmpty) return 'assets/images/${_word?.id}.webp';
    if (s.startsWith('assets/')) return s;
    if (s.contains('/')) return 'assets/$s';
    return 'assets/images/$s';
  }

  JujuPose get _pose {
    if (_listening) return JujuPose.listening;
    if (_step == _Step.done) return JujuPose.happy;
    return JujuPose.thinking;
  }

  @override
  Widget build(BuildContext context) {
    if (_word == null) {
      return const Scaffold(
          backgroundColor: AppColors.bg, body: Center(child: Text('🐪')));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 8),
              _jujuRow(),
              const SizedBox(height: 12),
              _preview(),
              const SizedBox(height: 12),
              if (_phrase != null) _phraseCard(),
              const SizedBox(height: 16),
              _choices(),
              const SizedBox(height: 16),
              _summary(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          _roundIcon(
              Icons.arrow_back_rounded, () => Navigator.maybePop(context)),
          Expanded(
            child: Text('Make it yours!',
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 24, color: AppColors.ink, weight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: _skip,
            style: TextButton.styleFrom(minimumSize: const Size(64, 64)),
            child: Text('Skip',
                style: AppTheme.english(
                    size: 16, color: AppColors.blue, weight: FontWeight.w700)),
          ),
        ],
      );

  Widget _roundIcon(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Icon(icon, color: AppColors.ink, size: 30),
        ),
      );

  Widget _jujuRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AudioService.instance.playing,
            builder: (_, talking, __) => Juju(
              pose: talking && !_listening ? JujuPose.talking : _pose,
              size: 110,
              motion: _step == _Step.done ? JujuMotion.bounce : JujuMotion.none,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: Text(_bubble,
                      style: AppTheme.english(
                          size: 17,
                          color: AppColors.ink,
                          weight: FontWeight.w600))
                  .animate(key: ValueKey(_bubble))
                  .fadeIn(duration: 250.ms),
            ),
          ),
        ],
      );

  Widget _preview() {
    final tint = _colour == null ? null : _swatch[_colour];
    final scale = _size == 'big' ? 1.2 : (_size == 'small' ? 0.65 : 1.0);
    final frame = _fem ? AppColors.feminine : AppColors.masculine;

    Widget img = Image.asset(
      _stickerPath,
      width: 170,
      height: 170,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Text('🎁', style: TextStyle(fontSize: 90)),
    );
    if (tint != null) {
      // BlendMode.color keeps the sticker's light/dark and white background,
      // and takes the hue from the chosen colour.
      img = ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.color), child: img);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: frame, width: 5),
        boxShadow: [
          if (tint != null)
            BoxShadow(
                color: tint.withOpacity(0.55), blurRadius: 28, spreadRadius: 4),
          const BoxShadow(color: AppColors.line, offset: Offset(0, 6)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            child: img,
          ),
          if (_fem)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.feminineBadge,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('ة',
                    style: AppTheme.arabic(size: 18, color: Colors.white)),
              ),
            ),
          if (_fun != null)
            Positioned(
              top: 6,
              right: 8,
              child: Text(_funEmoji[_fun] ?? '',
                      style: const TextStyle(fontSize: 46))
                  .animate(key: ValueKey(_fun))
                  .scale(
                      begin: const Offset(0.2, 0.2),
                      duration: 400.ms,
                      curve: Curves.elasticOut),
            ),
        ],
      ),
    );
  }

  Widget _phraseCard() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _sayPhrase,
              customBorder: const CircleBorder(),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.volume_up_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _phrase!,
                textDirection: TextDirection.rtl,
                style: AppTheme.arabic(
                    size: 30, color: AppColors.ink, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      )
          .animate(key: ValueKey(_phrase))
          .fadeIn(duration: 300.ms)
          .slideY(begin: 0.2);

  Widget _choices() {
    switch (_step) {
      case _Step.colour:
        return Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in _options)
                  _ChoiceTile(
                    selected: _colour == c.id,
                    onTap: () => _pickColour(c),
                    top: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _swatch[c.id] ?? AppColors.line,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.line, width: 3),
                      ),
                    ),
                    arabic: _colourForm(c),
                    english: c.en,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 240,
              child: BigButton(
                label: _listening ? 'Listening…' : 'Say it!',
                emoji: '🎤',
                style: BigButtonStyle.good,
                onTap: _listening ? () {} : _sayColour,
              ),
            ),
          ],
        );
      case _Step.size:
        return _adjRow(_Step.size, const ['big', 'small'], (id) {
          return Image.asset(_stickerPath,
              width: id == 'big' ? 64 : 32,
              height: id == 'big' ? 64 : 32,
              errorBuilder: (_, __, ___) => Text(id == 'big' ? '⬆️' : '⬇️',
                  style: const TextStyle(fontSize: 36)));
        }, _size);
      case _Step.fun:
        return _adjRow(
            _Step.fun,
            const ['happy', 'funny'],
            (id) =>
                Text(_funEmoji[id] ?? '', style: const TextStyle(fontSize: 48)),
            _fun);
      case _Step.done:
        return SizedBox(
          width: 300,
          child: BigButton(
              label: 'Make my story!',
              emoji: '📖',
              style: BigButtonStyle.accent,
              onTap: _goStory),
        ).animate().fadeIn().scale(
            begin: const Offset(0.8, 0.8),
            curve: Curves.elasticOut,
            duration: 600.ms);
    }
  }

  Widget _adjRow(_Step step, List<String> ids, Widget Function(String) top,
      String? chosen) {
    final repo = Repository.instance;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      children: [
        for (final id in ids)
          if (repo.adjective(id) != null)
            _ChoiceTile(
              selected: chosen == id,
              onTap: () => _pickAdj(step, id),
              top: SizedBox(height: 64, child: Center(child: top(id))),
              arabic: _adjForm(repo.adjective(id)!),
              english: repo.adjective(id)!.en,
            ),
      ],
    );
  }

  /// Chips of what the child picked so far – tap one to change it.
  Widget _summary() {
    final repo = Repository.instance;
    final chips = <Widget>[];
    if (_colour != null && repo.colour(_colour!) != null) {
      final c = repo.colour(_colour!)!;
      chips.add(_chip(
        Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: _swatch[c.id],
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line))),
        _colourForm(c),
        () => _edit(_Step.colour),
      ));
    }
    if (_hasSize && _size != null && repo.adjective(_size!) != null) {
      chips.add(_chip(const Text('📏', style: TextStyle(fontSize: 20)),
          _adjForm(repo.adjective(_size!)!), () => _edit(_Step.size)));
    }
    if (_fun != null && repo.adjective(_fun!) != null) {
      chips.add(_chip(
          Text(_funEmoji[_fun] ?? '', style: const TextStyle(fontSize: 20)),
          _adjForm(repo.adjective(_fun!)!),
          () => _edit(_Step.fun)));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: chips);
  }

  Widget _chip(Widget lead, String arabic, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            lead,
            const SizedBox(width: 8),
            Text(arabic,
                textDirection: TextDirection.rtl,
                style: AppTheme.arabic(size: 20, color: AppColors.ink)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 18, color: AppColors.muted),
          ]),
        ),
      );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.top,
    required this.arabic,
    required this.english,
    required this.selected,
    required this.onTap,
  });

  final Widget top;
  final String arabic;
  final String english;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: selected ? AppColors.good : AppColors.line,
              width: selected ? 4 : 2),
          boxShadow: [
            BoxShadow(
                color: selected ? AppColors.goodShadow : AppColors.line,
                offset: const Offset(0, AppTheme.shadowDepth)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            top,
            const SizedBox(height: 8),
            Text(arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: AppTheme.arabic(
                    size: 22, color: AppColors.ink, weight: FontWeight.w700)),
            Text(english,
                style: AppTheme.english(size: 14, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
