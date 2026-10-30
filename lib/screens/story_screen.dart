// Screen 11 – My story (story_screen.dart)
// 5 lines from StoryBuilder (port of story.py), one at a time, with word-by-word English.
// The child's chosen words are highlighted. Each line has a Listen button and an "I said it!" button.
// Every page has a picture from the Muse Image edit chain (MetaImage.storyPictures). It is cached.
// Juju paints while a picture is still coming. At the end the child taps "Add to my book" -> Screen 13.
//
// Route arguments (any one of these):
//   Map { 'wordId' or 'word' (String id or HuntWord), 'colour', 'size', 'fun',
//         'stickerFile' (File or path String, optional = sticker customised on Screen 10) }
//   Story      (already built)
//   HuntWord   (no choices; Screen 12 normally handles the "skipped customising" case)

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../services/audio.dart';
import '../services/meta_image.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/parent_tip.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

/// One word (or a noun group like "toothbrush") with its English gloss.
class _Chunk {
  final String arabic;
  final String english;
  final bool chosen;
  const _Chunk(this.arabic, this.english, this.chosen);
}

class _StoryScreenState extends State<StoryScreen> {
  final _audio = AudioService.instance;
  final _progress = ProgressService.instance;

  bool _ready = false;
  String? _error;

  HuntWord? _word;
  Story? _story;
  File? _customSticker;
  String? _colourId;

  int _page = 0;
  final Set<int> _said = {};
  bool _added = false;
  bool _justSaid = false;

  // Pictures: _pics[i] = picture for line i (null = keep previous). _resolved = finished pages.
  late List<File?> _pics;
  final Set<int> _resolved = {};
  bool _picturesDone = false;
  StreamSubscription<StoryPicture>? _picSub;

  // ----------------------------------------------------------------- setup

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready || _error != null) return;
    _setup(ModalRoute.of(context)?.settings.arguments);
  }

  void _setup(Object? args) {
    final repo = Repository.instance;
    try {
      String? colour, size, fun;
      Object? wordArg;

      if (args is Story) {
        _story = args;
        wordArg = args.wordId;
        colour = args.colour;
      } else if (args is HuntWord) {
        wordArg = args;
      } else if (args is Map) {
        wordArg = args['word'] ?? args['wordId'];
        colour = args['colour'] as String?;
        size = args['size'] as String?;
        fun = args['fun'] as String?;
        final sf = args['stickerFile'];
        if (sf is File) _customSticker = sf;
        if (sf is String && sf.isNotEmpty) _customSticker = File(sf);
      }

      _word = wordArg is HuntWord
          ? wordArg
          : (wordArg is String ? repo.huntWord(wordArg) : null);
      if (_word == null) throw 'No word was passed to the story screen.';
      _colourId = colour;

      _story ??= StoryBuilder(
        adjectives: {for (final a in repo.adjectives) a.id: a},
        colours: {for (final c in repo.colours) c.id: c},
      ).make(_word!,
          colour: colour,
          size: size,
          fun: fun,
          rng: Random(_seed(_word!.id, colour, size, fun)));

      _pics = List<File?>.filled(_story!.lines.length, null);
      _ready = true;
      _startPictures();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _playLine(first: true));
    } catch (e) {
      _error = '$e';
    }
  }

  /// Same choices -> same story every time, so the picture cache gets hits.
  int _seed(String id, String? c, String? s, String? f) =>
      '$id|$c|$s|$f'.codeUnits.fold(17, (h, u) => (h * 31 + u) & 0x7fffffff);

  void _startPictures() {
    _picSub = MetaImage.instance.storyPictures(_word!, _story!).listen(
      (p) {
        if (!mounted || p.index < 0 || p.index >= _pics.length) return;
        setState(() {
          _pics[p.index] = p.file;
          _resolved.add(p.index);
        });
      },
      onError: (_) => _finishPictures(),
      onDone: _finishPictures,
      cancelOnError: true,
    );
  }

  void _finishPictures() {
    if (mounted) setState(() => _picturesDone = true);
  }

  @override
  void dispose() {
    _picSub?.cancel();
    _audio.stop();
    super.dispose();
  }

  // ----------------------------------------------------------------- audio + actions

  SentenceLine get _line => _story!.lines[_page];
  bool get _isLast => _page == _story!.lines.length - 1;

  Future<void> _playLine({bool first = false}) async {
    if (!mounted) return;
    final page = _page;
    await _audio.say(_line.audioText, voice: TtsVoice.lesson);
    // Only once, on the first line: tell the child it's their turn.
    if (first && mounted && _page == page) {
      await _audio.playAsset('juju/juju_en_your_turn.mp3');
    }
  }

  void _goTo(int page) {
    if (page < 0 || page >= _story!.lines.length) return;
    _audio.stop();
    setState(() {
      _page = page;
      _justSaid = false;
    });
    _playLine();
  }

  Future<void> _onSaid() async {
    final first = !_said.contains(_page);
    setState(() {
      _said.add(_page);
      _justSaid = true;
    });
    if (first) _progress.addStars(1);
    if (!_isLast) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) _goTo(_page + 1);
    }
  }

  Future<void> _addToBook() async {
    if (_added) return;
    setState(() => _added = true);
    _progress.addToGallery(_word!.id, story: _story!);
    _progress.addStars(2);
    await _audio.playAsset('juju/juju_en_lesson_done.mp3');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, Routes.gallery);
  }

  // ----------------------------------------------------------------- word-by-word English

  // Frame words of the 5 story patterns (the same ones StoryBuilder uses). Compared without marks.
  static const _frameGloss = {
    'هذا': 'this is',
    'هذه': 'this is',
    'عندي': 'I have',
    'انا': 'I',
    'احب': 'like',
    'اين': 'where is',
  };

  String _key(String token) {
    var s = ArabicForms.normalise(ArabicForms.strip(token))
        .replaceAll(RegExp(r'[؟?،,.!]'), '')
        .trim();
    if (s.startsWith('ال') && s.length > 3) s = s.substring(2);
    return s;
  }

  List<_Chunk> _chunks(SentenceLine line) {
    final repo = Repository.instance;
    final word = _word!;

    final adjGloss = <String, String>{};
    for (final a in repo.adjectives) {
      adjGloss[_key(a.m)] = a.en;
      adjGloss[_key(a.f)] = a.en;
    }
    for (final c in repo.colours) {
      adjGloss[_key(c.m)] = c.en;
      adjGloss[_key(c.f)] = c.en;
    }
    final nounKeys = word.arabicWord.split(RegExp(r'\s+')).map(_key).toSet();
    final chosenKeys = line.highlight.map(_key).toSet();

    final tokens =
        line.arabic.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final out = <_Chunk>[];
    var i = 0;
    while (i < tokens.length) {
      final k = _key(tokens[i]);
      if (nounKeys.contains(k)) {
        // Noun group (handles two-word nouns like toothbrush).
        final group = <String>[];
        while (i < tokens.length && nounKeys.contains(_key(tokens[i]))) {
          group.add(tokens[i]);
          i++;
        }
        final definite =
            group.any((t) => ArabicForms.strip(t).startsWith('ال'));
        final noun = word.englishWord.toLowerCase();
        out.add(_Chunk(group.join(' '), definite ? 'the $noun' : noun, false));
        continue;
      }
      final en = _frameGloss[k] ?? adjGloss[k] ?? '';
      out.add(_Chunk(tokens[i], en, chosenKeys.contains(k)));
      i++;
    }
    // Put the question mark on the English of the last word too.
    if (line.arabic.trim().endsWith('؟') && out.isNotEmpty) {
      final last = out.removeLast();
      out.add(_Chunk(last.arabic, '${last.english}?', last.chosen));
    }
    return out;
  }

  // ----------------------------------------------------------------- pictures

  /// Picture for this page: its own, else the nearest earlier one, else the sticker.
  ImageProvider _pictureFor(int page) {
    for (var i = page; i >= 0; i--) {
      final f = _pics[i];
      if (f != null && _resolved.contains(i)) return FileImage(f);
    }
    return _stickerImage();
  }

  ImageProvider _stickerImage() {
    if (_customSticker != null && _customSticker!.existsSync())
      return FileImage(_customSticker!);
    final s = _word!.sticker;
    return AssetImage(s.startsWith('assets/') ? s : 'assets/images/$s');
  }

  bool get _painting => !_picturesDone && !_resolved.contains(_page);

  /// Fallback glow when there is no customised sticker (English ids only, no Arabic here).
  static const _glow = {
    'red': Color(0xFFE53935),
    'blue': Color(0xFF1E88E5),
    'green': Color(0xFF43A047),
    'yellow': Color(0xFFFDD835),
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF212121),
    'brown': Color(0xFF8D6E63),
    'orange': Color(0xFFFB8C00),
    'pink': Color(0xFFEC407A),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
  };

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorView();
    if (!_ready) {
      return const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(),
              const SizedBox(height: 8),
              Text(
                'My ${_word!.englishWord.toLowerCase()} story',
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 24, weight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              _pictureCard(),
              const SizedBox(height: 14),
              _sentenceCard(),
              const SizedBox(height: 14),
              _actions(),
              const SizedBox(height: 16),
              const ParentTip(
                text:
                    'Read the story together: you read a line, your child points to the picture '
                    'and says it back. Swap roles for the last line!',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final n = _story!.lines.length;
    return Row(
      children: [
        SizedBox(
          width: AppTheme.minTap,
          height: AppTheme.minTap,
          child: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.ink, size: 30),
            onPressed: () =>
                _page > 0 ? _goTo(_page - 1) : Navigator.maybePop(context),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(n, (i) {
              final done = _said.contains(i);
              final current = i == _page;
              return GestureDetector(
                onTap: (done || i <= _page) ? () => _goTo(i) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: current ? 28 : 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.good
                        : (current ? AppColors.accent : AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }),
          ),
        ),
        ListenableBuilder(
          listenable: _progress,
          builder: (_, __) => Row(children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 28),
            const SizedBox(width: 2),
            Text('${_progress.stars}',
                style: AppTheme.english(size: 18, weight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _pictureCard() {
    final glow =
        (_customSticker == null && _colourId != null) ? _glow[_colourId] : null;
    return AspectRatio(
      aspectRatio: 1.25,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: const [
            BoxShadow(color: AppColors.line, offset: Offset(0, 6))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: Container(
                  key: ValueKey('pic-$_page-${_resolved.contains(_page)}'),
                  decoration: glow == null
                      ? null
                      : BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: glow.withOpacity(0.45),
                                blurRadius: 40,
                                spreadRadius: 6)
                          ],
                        ),
                  child: Image(
                    image: _pictureFor(_page),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Text('🖼️', style: TextStyle(fontSize: 64))),
                  ),
                ),
              ),
            ),
            if (_painting)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.line, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Juju(
                          pose: JujuPose.painting,
                          size: 56,
                          motion: JujuMotion.wiggle),
                      const SizedBox(width: 4),
                      Text('Painting…',
                          style: AppTheme.english(
                              size: 14,
                              weight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 250.ms),
          ],
        ),
      ),
    );
  }

  Widget _sentenceCard() {
    final line = _line;
    final chunks = _chunks(line);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          Text('Sentence ${_page + 1} of ${_story!.lines.length}',
              style: AppTheme.english(
                  size: 14, weight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in chunks)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.chosen ? AppColors.tip : AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: c.chosen ? AppColors.accent : AppColors.line,
                          width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.arabic,
                            textDirection: TextDirection.rtl,
                            style: AppTheme.arabic(
                                size: 34,
                                color: c.chosen
                                    ? AppColors.highlight
                                    : AppColors.ink,
                                weight: FontWeight.w700)),
                        if (c.english.isNotEmpty)
                          Text(c.english,
                              textDirection: TextDirection.ltr,
                              style: AppTheme.english(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          )
              .animate(key: ValueKey(_page))
              .fadeIn(duration: 300.ms)
              .slideX(begin: -0.08),
          const SizedBox(height: 12),
          Text(line.phonetic,
              textAlign: TextAlign.center,
              style: AppTheme.english(
                  size: 17, weight: FontWeight.w700, color: AppColors.blue)),
          const SizedBox(height: 2),
          Text(line.english,
              textAlign: TextAlign.center,
              style: AppTheme.english(
                  size: 16, weight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text('← Arabic reads right to left',
              style: AppTheme.english(size: 13, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _actions() {
    final saidThis = _said.contains(_page);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _audio.playing,
          builder: (_, talking, __) => Juju(
            pose: _justSaid
                ? JujuPose.happy
                : (talking ? JujuPose.talking : JujuPose.listening),
            size: 90,
            motion: _justSaid ? JujuMotion.pop : JujuMotion.none,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BigButton(
                label: 'Listen',
                emoji: '🔊',
                style: BigButtonStyle.accent,
                height: 64,
                onTap: _playLine,
              ),
              const SizedBox(height: 10),
              if (_isLast && saidThis)
                BigButton(
                  label: _added ? 'Added!' : 'Add to my book',
                  emoji: '📖',
                  style: BigButtonStyle.good,
                  height: 72,
                  onTap: _added ? null : _addToBook,
                ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack)
              else
                BigButton(
                  label: 'I said it!',
                  emoji: '⭐',
                  style: BigButtonStyle.good,
                  height: 72,
                  onTap: _onSaid,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorView() => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Juju(pose: JujuPose.confused, size: 140),
                const SizedBox(height: 12),
                Text('Oops! Juju lost the story.',
                    style: AppTheme.english(size: 20, weight: FontWeight.w800)),
                const SizedBox(height: 16),
                BigButton(
                  label: 'Back to the hunt',
                  emoji: '📷',
                  style: BigButtonStyle.good,
                  onTap: () => Navigator.pushNamedAndRemoveUntil(
                      context, Routes.huntHub, (r) => r.isFirst),
                ),
              ]),
            ),
          ),
        ),
      );
}
