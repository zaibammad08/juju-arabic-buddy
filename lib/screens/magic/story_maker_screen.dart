// Story Maker – DRAWING. The child draws something from home with coloured crayons;
// Muse Spark guesses what it is and its colour; the app's StoryBuilder (port of
// story.py) writes a 5-line Arabic story about it, shown next to the child's drawing.
// Each line is shown word by word: tap a word to hear it (pre-made clips only, no TTS).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/arabic_forms.dart';
import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/meta_games.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/juju.dart';
import '../../widgets/loading_match.dart';
import 'magic_common.dart';

// Crayon colours, keyed by the ids in colours.json.
const _crayons = <String, Color>{
  'red': Color(0xFFE5536B),
  'orange': Color(0xFFF08A24),
  'yellow': Color(0xFFF5B83D),
  'green': Color(0xFF1FA67A),
  'blue': Color(0xFF2F6FDE),
  'purple': Color(0xFF8A5CD6),
  'pink': Color(0xFFF49AC1),
  'brown': Color(0xFF8B5A2B),
  'black': Color(0xFF0B2A3D),
};

// The small words every story uses. Pre-made clips in assets/audio/story/.
// Keys are bare letters (no marks, أ/إ/آ → ا) – see _key().
const _storyWords = <String, String>{
  'هذا': 'story/word_hadha.mp3',
  'هذه': 'story/word_hadhihi.mp3',
  'عندي': 'story/word_indi.mp3',
  'انا': 'story/word_ana.mp3',
  'احب': 'story/word_uhibbu.mp3',
  'اين': 'story/word_ayna.mp3',
};

/// Compare key for an Arabic word: no tashkeel, no punctuation,
/// hamza-alifs → ا, and no leading الْ (so الْبَابُ matches بَاب).
String _key(String s) {
  var k = s
      .replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp('[؟?!.،,]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .trim();
  if (k.startsWith('ال') && k.length > 3) k = k.substring(2);
  return k;
}

class _Tok {
  final String text; // as shown, with all marks
  final String? audio; // assets/audio/... path, null = no clip
  const _Tok(this.text, this.audio);
}

enum _Phase { draw, choose, story }

class StoryMakerScreen extends StatefulWidget {
  const StoryMakerScreen({super.key});
  @override
  State<StoryMakerScreen> createState() => _StoryMakerScreenState();
}

class _StoryMakerScreenState extends State<StoryMakerScreen> {
  final _rng = Random();
  final _pad = DrawPadController()..width = 14;
  String _crayon = 'red';
  _Phase _phase = _Phase.draw;
  Uint8List? _drawing; // in memory only
  HuntWord? _word;
  String _colour = '';
  Story? _story;
  int _line = 0;
  List<HuntWord> _choices = [];
  bool _rewarded = false;

  List<List<_Tok>> _tokens = []; // one list of words per story line
  int _activeTok = -1; // word currently speaking
  int _playId = 0; // bumps to cancel a running read-through

  @override
  void initState() {
    super.initState();
    _pad.color = _crayons[_crayon]!;
    MagicData.load().then((_) => playJuju('story_draw'));
  }

  @override
  void dispose() {
    _playId++;
    AudioService.instance.stop();
    _pad.dispose();
    super.dispose();
  }

  String _colourOfPad() {
    final c = _pad.mainColour;
    if (c == null) return '';
    for (final e in _crayons.entries) {
      if (e.value == c) return e.key;
    }
    return '';
  }

  Future<void> _done() async {
    if (_pad.isEmpty) return;
    final png = await _pad.toPng();
    if (png == null || !mounted) return;
    final words = Repository.instance.huntWords
        .where((w) => str(w.sticker).isNotEmpty)
        .toList();
    final names = [for (final w in words) str(w.englishWord).toLowerCase()];
    final colourIds = [for (final c in Repository.instance.colours) str(c.id)];
    final guess = await waitWithMatch(
        context, MetaGames.instance.drawingGuess(png, names, colourIds),
        message: "I'm looking at your picture…");
    if (!mounted) return;
    _drawing = png;
    final padColour = _colourOfPad();
    final colour =
        (guess?.colour.isNotEmpty ?? false) ? guess!.colour : padColour;
    final thing = guess?.thing ?? '';
    final word = thing.isEmpty ? null : huntWordByEnglish(thing);
    if (word != null) {
      _makeStory(word, colour);
    } else {
      final pool = List<HuntWord>.of(words)..shuffle(_rng);
      setState(() {
        _colour = colour;
        _choices = pool.take(3).toList();
        _phase = _Phase.choose;
      });
    }
  }

  /// Splits a story line into words and gives each one its pre-made clip.
  List<_Tok> _tokenise(String line, HuntWord w) {
    final repo = Repository.instance;
    final map = <String, String>{..._storyWords};
    // the object (both parts for idafa words like فُرْشَاةُ أَسْنَانٍ)
    for (final p in str(w.arabicWord).split(' ')) {
      if (p.trim().isNotEmpty) map[_key(p)] = 'words/${str(w.id)}_word.mp3';
    }
    for (final c in repo.colours) {
      final id = str(c.id);
      map.putIfAbsent(_key(str(c.m)), () => 'colours/colour_${id}_m.mp3');
      map.putIfAbsent(_key(str(c.f)), () => 'colours/colour_${id}_f.mp3');
    }
    for (final a in repo.adjectives) {
      final id = str(a.id);
      map.putIfAbsent(_key(str(a.m)), () => 'adjectives/adj_${id}_m.mp3');
      map.putIfAbsent(_key(str(a.f)), () => 'adjectives/adj_${id}_f.mp3');
    }
    return [
      for (final t in line.split(' '))
        if (t.trim().isNotEmpty) _Tok(t, map[_key(t)])
    ];
  }

  void _makeStory(HuntWord word, String colour) {
    final repo = Repository.instance;
    final builder = StoryBuilder(
      adjectives: {for (final a in repo.adjectives) str(a.id): a},
      colours: {for (final c in repo.colours) str(c.id): c},
    );
    final story = builder.make(word,
        colour: colour.isEmpty ? 'red' : colour,
        size: 'big',
        fun: 'happy',
        rng: _rng);
    setState(() {
      _word = word;
      _colour = colour;
      _story = story;
      _tokens = [for (final l in story.lines) _tokenise(str(l.arabic), word)];
      _line = 0;
      _activeTok = -1;
      _phase = _Phase.story;
    });
    _playLine();
  }

  Future<void> _playTok(_Tok t) async {
    try {
      await AudioService.instance.playAsset(t.audio!, wait: true);
    } catch (_) {
      // clip missing – skip quietly
    }
  }

  /// Reads the current line word by word, lighting up each word.
  Future<void> _playLine() async {
    if (_line >= _tokens.length) return;
    final id = ++_playId;
    await AudioService.instance.stop();
    final toks = _tokens[_line];
    for (var i = 0; i < toks.length; i++) {
      if (toks[i].audio == null) continue;
      if (id != _playId || !mounted) return;
      setState(() => _activeTok = i);
      await _playTok(toks[i]);
    }
    if (id == _playId && mounted) setState(() => _activeTok = -1);
  }

  /// Child taps one word.
  Future<void> _tapTok(int i) async {
    final t = _tokens[_line][i];
    if (t.audio == null) return;
    final id = ++_playId;
    await AudioService.instance.stop();
    if (!mounted) return;
    setState(() => _activeTok = i);
    await _playTok(t);
    if (id == _playId && mounted) setState(() => _activeTok = -1);
  }

  void _nextLine() {
    final s = _story;
    if (s == null) return;
    if (_line < s.lines.length - 1) {
      setState(() {
        _line++;
        _activeTok = -1;
      });
      _playLine();
    } else if (!_rewarded) {
      ProgressService.instance.addStars(3);
      setState(() => _rewarded = true);
    }
  }

  void _restart() {
    _playId++;
    AudioService.instance.stop();
    _pad.clear();
    setState(() {
      _phase = _Phase.draw;
      _drawing = null;
      _story = null;
      _word = null;
      _tokens = [];
      _activeTok = -1;
      _rewarded = false;
    });
    playJuju('story_draw');
  }

  @override
  Widget build(BuildContext context) {
    return MagicScaffold(
      title: 'Story Maker',
      child: switch (_phase) {
        _Phase.draw => _drawView(),
        _Phase.choose => _chooseView(),
        _Phase.story => _storyView(),
      },
    );
  }

  Widget _drawView() {
    return Column(children: [
      JujuSays(
        pose: JujuPose.painting,
        size: 80,
        text: 'Draw something from your home!',
        sub: 'Then I will tell its story.',
        onListen: () => playJuju('story_draw'),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line, width: 3),
          ),
          child: DrawPad(controller: _pad),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in _crayons.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                label: '${e.key} crayon',
                child: GestureDetector(
                  onTap: () => setState(() {
                    _crayon = e.key;
                    _pad.color = e.value;
                  }),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: e.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color:
                              _crayon == e.key ? AppColors.ink : Colors.white,
                          width: 4),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        RoundIcon(
            icon: Icons.undo_rounded,
            label: 'Undo',
            onTap: _pad.undo,
            size: 64),
        const SizedBox(width: 12),
        Expanded(
            child: GameButton(
                label: 'Juju, look!',
                icon: Icons.auto_stories_rounded,
                onTap: _done)),
      ]),
    ]);
  }

  Widget _chooseView() {
    return Column(children: [
      const JujuSays(
        pose: JujuPose.thinking,
        text: 'What a lovely picture!',
        sub: 'Is it one of these?',
      ),
      const SizedBox(height: 12),
      if (_drawing != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(_drawing!, height: 150, fit: BoxFit.contain),
        ),
      const SizedBox(height: 12),
      Expanded(
        child: Column(children: [
          for (final w in _choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _makeStory(w, _colour),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(color: AppColors.line, offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(children: [
                    StickerImage(str(w.sticker), size: 64),
                    const SizedBox(width: 12),
                    arabicLine(str(w.arabicWord), size: 30),
                    const Spacer(),
                    Text(str(w.englishWord),
                        style: AppTheme.english(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.muted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      GameButton(
        label: 'Draw again',
        icon: Icons.brush_rounded,
        color: AppColors.surface,
        shadow: AppColors.line,
        textColor: AppColors.ink,
        height: 64,
        onTap: _restart,
      ),
    ]);
  }

  Widget _wordsOfLine(SentenceLine line) {
    final toks = _line < _tokens.length ? _tokens[_line] : const <_Tok>[];
    final chosen = {
      for (final h in [...?line.highlight]) _key(str(h))
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 8,
        children: [
          for (var i = 0; i < toks.length; i++)
            Semantics(
              button: toks[i].audio != null,
              label: toks[i].text,
              child: GestureDetector(
                onTap: () => _tapTok(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: i == _activeTok
                        ? AppColors.accent.withOpacity(0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: toks[i].audio == null
                            ? Colors.transparent
                            : AppColors.line,
                        width: 2),
                  ),
                  child: arabicLine(toks[i].text,
                      size: 34,
                      color: chosen.contains(_key(toks[i].text))
                          ? AppColors.highlight
                          : AppColors.ink),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _storyView() {
    final s = _story;
    final w = _word;
    if (s == null || w == null || s.lines.isEmpty) return const SizedBox();
    final line = s.lines[_line];
    final last = _line == s.lines.length - 1;
    return Column(children: [
      Row(children: [
        if (_drawing != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              color: Colors.white,
              child: Image.memory(_drawing!,
                  width: 130, height: 130, fit: BoxFit.contain),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My story about',
                style: AppTheme.english(
                    size: 14, weight: FontWeight.w700, color: AppColors.muted)),
            arabicLine(str(w.arabicWord), size: 38, color: AppColors.highlight),
            Text(str(w.englishWord),
                style: AppTheme.english(
                    size: 15, weight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Expanded(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 4))
            ],
          ),
          child: Column(children: [
            Text('${_line + 1} / ${s.lines.length}',
                style: AppTheme.english(
                    size: 14, weight: FontWeight.w800, color: AppColors.muted)),
            const Spacer(),
            _wordsOfLine(line),
            const SizedBox(height: 8),
            Text(str(line.english),
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 16, weight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 4),
            Text('Tap a word to hear it',
                style: AppTheme.english(
                    size: 13, weight: FontWeight.w600, color: AppColors.muted)),
            const Spacer(),
            RoundIcon(
                icon: Icons.volume_up_rounded,
                label: 'Hear this line',
                onTap: _playLine,
                color: AppColors.accent,
                shadow: AppColors.accentShadow,
                size: 64),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      if (last && _rewarded)
        Row(children: [
          const Juju(pose: JujuPose.proud, size: 72, motion: JujuMotion.pop),
          const SizedBox(width: 10),
          Expanded(
              child: GameButton(
                  label: 'Draw another',
                  icon: Icons.brush_rounded,
                  onTap: _restart)),
        ])
      else
        GameButton(
            label: last ? 'The end!' : 'Next line',
            icon: last ? Icons.star_rounded : Icons.arrow_forward_rounded,
            onTap: _nextLine),
    ]);
  }
}
