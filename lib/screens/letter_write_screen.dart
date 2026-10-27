// Screen 6 – Write (lib/screens/letter_write_screen.dart)
//
// 6 writings per letter: the letter itself + 5 lesson words.
// Each writing has two steps:
//   1) TRACE  – grey guide shape, checked on the phone (coverage, like the lesson pages)
//   2) WRITE  – blank canvas, the child writes alone; Muse Spark kindly checks it
// Then a celebration: Juju's board pose + the child's OWN writing on the board
// (placed by the app, never changed by AI) + the word's sticker bouncing.
// Each writing is saved to the Writing wall (Screen 14) via ProgressService.addWriting.
//
// Never blocks the child: after 2 tries in either step we praise and move on.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';

import '../services/audio.dart';
import '../services/progress.dart';
import '../services/meta_text.dart';
import '../widgets/juju.dart';

// ---------------------------------------------------------------------------
// Tuning
// ---------------------------------------------------------------------------

/// Where the blank board sits inside each board pose image, as fractions of
/// the (square) Juju image: left, top, width, height. Tune to the real images
/// (for board 3 you can copy the values you tuned in alphabet_screen.dart).
const Map<int, Rect> _boardRects = {
  1: Rect.fromLTWH(0.50, 0.16, 0.44, 0.40), // easel beside Juju
  2: Rect.fromLTWH(0.22, 0.50, 0.56, 0.32), // board leaning on her legs
  3: Rect.fromLTWH(0.30, 0.50, 0.40, 0.26), // board hanging from her neck
};
const double _shapePass = 0.50;
const int _wordsPerLetter = 5; // + the letter itself = 6 writings
const double _traceNeedCover = 0.55; // share of the shape the finger must cover
const double _traceMaxOutside = 0.45; // share of ink allowed off the shape
const double _writeBrush = 11;

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _WriteItem {
  const _WriteItem({
    required this.plain,
    required this.display,
    required this.english,
    this.sticker,
    this.emoji,
    this.isLetter = false,
  });

  /// Plain letters (no marks) – used for the tracing shape and the AI check.
  final String plain;

  /// Exactly as in the data file (full marks) – shown on screen.
  final String display;
  final String english;
  final String? sticker; // raw value from the lesson file
  final String? emoji;
  final bool isLetter;

  String? get stickerPath {
    final s = sticker;
    if (s == null || s.isEmpty) return null;
    return s.contains('/') ? s : 'assets/images/$s.webp';
  }

  String get wordId {
    final s = sticker;
    if (s == null || s.isEmpty) return plain;
    return s.split('/').last.split('.').first;
  }
}

enum _Mode { trace, write }

enum _Phase { work, celebrate, finished }

class _TraceScore {
  const _TraceScore(this.cover, this.outside, this.inkPixels);
  final double cover, outside;
  final int inkPixels;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LetterWriteScreen extends StatefulWidget {
  const LetterWriteScreen({super.key});

  @override
  State<LetterWriteScreen> createState() => _LetterWriteScreenState();
}

class _LetterWriteScreenState extends State<LetterWriteScreen> {
  String? _letter;
  List<_WriteItem> _items = const [];
  int _index = 0;
  final Set<int> _done = {};

  _Phase _phase = _Phase.work;
  _Mode _mode = _Mode.trace;
  bool _busy = false;
  bool _showHint = false;
  int _traceTries = 0;
  int _writeTries = 0;

  JujuPose _pose = JujuPose.pencil;
  String _message = '';

  // drawing
  final List<List<Offset>> _strokes = [];
  final ValueNotifier<int> _tick = ValueNotifier(0);
  Size? _canvasSize;

  // celebration
  Uint8List? _lastPng;
  int _lastBoard = 1;
  bool _skillMarked = false;

  _WriteItem get _item => _items[_index];

  double get _traceBrush {
    final s = _canvasSize;
    if (s == null) return 18;
    return math.max(16, _Guide.layout(s, _item.plain).fontSize * 0.12);
  }

  // ---------------------------------------------------------------- setup

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_letter != null) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    _letter = (arg is String && arg.isNotEmpty)
        ? Repository.baseLetter(arg)
        : ProgressService.instance.currentLetter;
    _items = _buildItems(_letter!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startItem(0));
  }

  @override
  void dispose() {
    AudioService.instance.stop();
    _tick.dispose();
    super.dispose();
  }

  List<_WriteItem> _buildItems(String letter) {
    final items = <_WriteItem>[
      _WriteItem(
          plain: letter,
          display: letter,
          english: 'the letter',
          isLetter: true),
    ];
    final words = <_WriteItem>[];
    final seen = <String>{};

    final dynamic lesson = Repository.instance.lesson(letter);
    if (lesson is Map) {
      final traceList = (lesson['trace'] is List)
          ? (lesson['trace'] as List).map((e) => '$e').toSet()
          : <String>{};
      final raw = lesson['words'];
      if (raw is List) {
        final parsed = <_WriteItem>[];
        for (final w in raw) {
          if (w is! Map) continue;
          final display = '${w['word'] ?? ''}';
          if (display.isEmpty) continue;
          final plain = (w['plain'] != null && '${w['plain']}'.isNotEmpty)
              ? '${w['plain']}'
              : ArabicForms.strip(display);
          parsed.add(_WriteItem(
            plain: plain,
            display: display,
            english: '${w['english'] ?? ''}',
            sticker: w['sticker']?.toString(),
            emoji: w['emoji']?.toString(),
          ));
        }
        // words the founder's page already traces come first
        parsed.sort((a, b) {
          final ai = traceList.contains(a.plain) ? 0 : 1;
          final bi = traceList.contains(b.plain) ? 0 : 1;
          return ai.compareTo(bi);
        });
        for (final p in parsed) {
          if (seen.add(p.plain)) words.add(p);
        }
      }
    }

    // fallback / top-up from lesson_words.json
    if (words.length < _wordsPerLetter) {
      for (final lw in Repository.instance.lessonWordsFor(letter)) {
        final plain = ArabicForms.strip(lw.arabic);
        if (!seen.add(plain)) continue;
        words.add(_WriteItem(
          plain: plain,
          display: lw.arabic,
          english: lw.english,
          sticker: lw.sticker,
        ));
        if (words.length >= _wordsPerLetter) break;
      }
    }

    items.addAll(words.take(_wordsPerLetter));
    return items;
  }

  // ---------------------------------------------------------------- flow

  void _startItem(int i) {
    if (!mounted) return;
    setState(() {
      _index = i;
      _phase = _Phase.work;
      _mode = _Mode.trace;
      _traceTries = 0;
      _writeTries = 0;
      _showHint = false;
      _busy = false;
      _pose = JujuPose.pencil;
      _strokes.clear();
    });
    _tick.value++;
    _say(_item.isLetter
        ? 'Trace the grey letter with your finger.'
        : 'Trace the grey word with your finger.');
  }

  void _say(String msg, {String? asset}) {
    setState(() => _message = msg);
    if (asset != null) {
      AudioService.instance
          .playOrSay(asset: asset, text: msg, voice: TtsVoice.jujuEnglish);
    } else {
      AudioService.instance.say(msg, voice: TtsVoice.jujuEnglish);
    }
  }

  void _listen() {
    final it = _item;
    if (it.isLetter) {
      // letter name: mp3 letters/<slug>_name.mp3, else TTS of the name from the lesson file
      final dynamic lesson = Repository.instance.lesson(it.plain);
      String slug = '';
      String nameText = it.plain;
      if (lesson is Map) {
        slug = '${lesson['name'] ?? ''}';
        final ts = lesson['trace_say'];
        if (ts is List &&
            ts.isNotEmpty &&
            ts.first is List &&
            (ts.first as List).isNotEmpty) {
          nameText = '${(ts.first as List).first}';
        }
      }
      AudioService.instance.playOrSay(
        asset: slug.isEmpty ? null : 'letters/${slug}_name.mp3',
        text: ArabicForms.forSpeech(nameText),
        voice: TtsVoice.lessonWord,
      );
    } else {
      // word: mp3 words/<sticker id>_word.mp3, else TTS (no sukun)
      AudioService.instance.playOrSay(
        asset: 'words/${it.wordId}_word.mp3',
        text: ArabicForms.forSpeech(it.display),
        voice: TtsVoice.lessonWord,
      );
    }
  }

  void _clear() {
    _strokes.clear();
    _tick.value++;
    setState(() => _pose = JujuPose.pencil);
  }

  Future<void> _onDone() async {
    if (_busy) return;
    if (_strokes.isEmpty) {
      _say('Use your finger to write!');
      return;
    }
    if (_mode == _Mode.trace) {
      await _checkTrace();
    } else {
      await _checkWriting();
    }
  }

  Future<void> _checkTrace() async {
    final size = _canvasSize;
    if (size == null) return;
    setState(() => _busy = true);
    final score = await _scoreTrace(size);
    if (!mounted) return;
    setState(() => _busy = false);

    final ok = score.inkPixels > 0 &&
        score.outside <= _traceMaxOutside &&
        score.cover >= _traceNeedCover;

    if (ok || _traceTries >= 1) {
      // passed, or second try: praise and move on (never block)
      _listen();
      setState(() {
        _mode = _Mode.write;
        _pose = JujuPose.happy;
        _strokes.clear();
      });
      _tick.value++;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      _say(ok
          ? 'Beautiful! Now write it all by yourself.'
          : 'Great trying! Now write it all by yourself.');
      return;
    }

    _traceTries++;
    setState(() => _pose = JujuPose.encourage);
    if (score.outside > _traceMaxOutside) {
      _say('Try to stay on the grey shape. Tap Again to start over.');
    } else {
      _say('Almost! Trace the whole shape, including the dots.');
    }
  }

  Future<void> _checkWriting() async {
    final checkPng =
        await _exportWriting(whiteBackground: true); // for Muse Spark
    final boardPng = await _exportWriting(); // transparent, for board + wall
    if (checkPng == null || boardPng == null) {
      _say('Use your finger to write!');
      return;
    }
    setState(() {
      _busy = true;
      _pose = JujuPose.thinking;
      _message = 'Let me look…';
    });

    final shape = await _localShapeScore();
    debugPrint(
        'Write check "${_item.plain}": shape ${shape.toStringAsFixed(2)} (pass $_shapePass)');

    bool? looksRight;
    String aiMessage = '';
    if (shape < _shapePass) {
      looksRight = false;
      aiMessage =
          'Hmm, that looks a bit different. Look at the shape and write it once more.';
    } else {
      try {
        final r =
            await MetaText.instance.checkHandwriting(checkPng, _item.plain);
        looksRight = r.looksRight;
        aiMessage = '${r.message ?? ''}'.trim();
      } catch (_) {
        looksRight = null; // couldn't check → praise and move on
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (looksRight == false && _writeTries < 1) {
      _writeTries++;
      setState(() {
        _pose = JujuPose.encourage;
        _showHint = true; // show the grey shape faintly to help
        _strokes.clear();
      });
      _tick.value++;
      _say(aiMessage.isNotEmpty
          ? aiMessage
          : 'Good try! Look at the shape and write it once more.');
      return;
    }

    final praise = looksRight == false
        ? null // second try: generic "great trying"
        : (aiMessage.isNotEmpty ? aiMessage : 'Wonderful writing!');
    await _celebrate(boardPng, praise);
  }

  Future<void> _celebrate(Uint8List png, String? praise) async {
    final letter = _letter!;
    final entry = await ProgressService.instance.addWriting(
      letter: letter,
      target: _item.display,
      png: png,
      wordId: _item.wordId,
    );
    await ProgressService.instance.addStars(1);
    if (!mounted) return;

    setState(() {
      _lastPng = png;
      _lastBoard = _boardOf(entry);
      _done.add(_index);
      _phase = _Phase.celebrate;
    });

    if (praise == null) {
      _say('Great trying!', asset: 'juju/juju_en_great_trying.mp3');
    } else {
      _say(praise);
    }
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted && _phase == _Phase.celebrate) _listen();
  }

  int _boardOf(dynamic entry) {
    try {
      final b = entry.board;
      if (b is int && b >= 1 && b <= 3) return b;
    } catch (_) {}
    return 1 + math.Random().nextInt(3);
  }

  Future<void> _next() async {
    // next item not yet done, else finish
    for (var k = 1; k <= _items.length; k++) {
      final i = (_index + k) % _items.length;
      if (!_done.contains(i)) {
        _startItem(i);
        return;
      }
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() {
      _phase = _Phase.finished;
      _pose = JujuPose.gradCap;
    });
    if (!_skillMarked) {
      _skillMarked = true;
      await ProgressService.instance.markSkillDone(_letter!, 'write');
      await ProgressService.instance.addStars(2);
    }
    _say('You wrote them all! Super writer!',
        asset: 'juju/juju_en_skill_write_done.mp3');
  }

  // ---------------------------------------------------------------- drawing

  void _addPoint(Offset p, {bool start = false}) {
    if (_busy || _phase != _Phase.work) return;
    if (start || _strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(p);
    _tick.value++;
  }

  Future<_TraceScore> _scoreTrace(Size size) async {
    const s = 0.34; // score on a small copy – fast and good enough
    final w = math.max(1, (size.width * s).ceil());
    final h = math.max(1, (size.height * s).ceil());
    final guide = _Guide.layout(size, _item.plain);
    final brush = _traceBrush;

    Future<Uint8List> render(void Function(Canvas c) draw) async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.scale(s);
      draw(c);
      final img = await rec.endRecording().toImage(w, h);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      return bd!.buffer.asUint8List();
    }

    final mask = await render((c) => guide.paintFill(c, Colors.black));
    final wide = await render((c) {
      guide.paintFill(c, Colors.black);
      guide.paintStroke(c, Colors.black, brush * 1.6);
    });
    final ink =
        await render((c) => _paintStrokes(c, _strokes, Colors.black, brush));

    var tot = 0, cov = 0, inkN = 0, out = 0;
    for (var i = 3; i < mask.length; i += 4) {
      final m = mask[i] > 100, k = ink[i] > 50;
      if (m) {
        tot++;
        if (k) cov++;
      }
      if (k) {
        inkN++;
        if (wide[i] < 50) out++;
      }
    }
    return _TraceScore(
        tot == 0 ? 0 : cov / tot, inkN == 0 ? 0 : out / inkN, inkN);
  }

  /// The child's own writing, cropped, dark ink on white, as PNG.
  /// The child's own writing, cropped, dark ink, as PNG.
  /// Transparent by default (board/wall); white background for the AI check.
  Future<Uint8List?> _exportWriting({bool whiteBackground = false}) async {
    final pts = _strokes.expand((s) => s).toList();
    if (pts.length < 4) return null;
    var l = pts.first.dx, t = pts.first.dy, r = l, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    final box = Rect.fromLTRB(l, t, r, b).inflate(_writeBrush + 16);
    const scale = 2.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(scale);
    c.translate(-box.left, -box.top);
    if (whiteBackground) c.drawRect(box, Paint()..color = Colors.white);
    _paintStrokes(c, _strokes, AppColors.ink, _writeBrush);
    final img = await rec
        .endRecording()
        .toImage((box.width * scale).ceil(), (box.height * scale).ceil());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd?.buffer.asUint8List();
  }

  Future<Uint8List> _renderAlpha(
      int w, int h, void Function(Canvas c) draw) async {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    final img = await rec.endRecording().toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return bd!.buffer.asUint8List();
  }

  /// Compares the child's writing with the target shape on a 96×96 grid.
  /// Both are scaled to fit the same box (aspect kept), then:
  /// precision = child ink that lies near the target, recall = target covered by child ink.
  /// Returns their harmonic mean (0–1). 1.0 if it can't judge.
  Future<double> _localShapeScore() async {
    const n = 96;
    const pad = 8.0;
    const inner = n - 2 * pad;

    // child's box
    final pts = _strokes.expand((s) => s).toList();
    if (pts.isEmpty) return 0;
    var l = pts.first.dx, t = pts.first.dy, r = l, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    final cw = math.max(r - l, 1.0), ch = math.max(b - t, 1.0);
    final cs = inner / math.max(cw, ch);
    final cdx = pad + (inner - cw * cs) / 2 - l * cs;
    final cdy = pad + (inner - ch * cs) / 2 - t * cs;

    // target's tight box (render big once, scan for ink)
    const fs = 160.0;
    TextPainter glyph(Paint fg) => TextPainter(
          text: TextSpan(
            text: _item.plain,
            style: GoogleFonts.balooBhaijaan2(
                fontSize: fs, fontWeight: FontWeight.w800, foreground: fg),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
    final fill = glyph(Paint()..color = Colors.black);
    final tw = fill.width.ceil() + 2, th = fill.height.ceil() + 2;
    final big =
        await _renderAlpha(tw, th, (c) => fill.paint(c, const Offset(1, 1)));
    var gx1 = tw, gy1 = th, gx2 = -1, gy2 = -1;
    for (var y = 0; y < th; y++) {
      for (var x = 0; x < tw; x++) {
        if (big[(y * tw + x) * 4 + 3] > 100) {
          if (x < gx1) gx1 = x;
          if (x > gx2) gx2 = x;
          if (y < gy1) gy1 = y;
          if (y > gy2) gy2 = y;
        }
      }
    }
    if (gx2 < 0) return 1.0;
    final gw = (gx2 - gx1 + 1).toDouble(), gh = (gy2 - gy1 + 1).toDouble();
    final gs = inner / math.max(gw, gh);
    final gdx = pad + (inner - gw * gs) / 2 - gx1 * gs;
    final gdy = pad + (inner - gh * gs) / 2 - gy1 * gs;

    void toGlyph(Canvas c) {
      c.translate(gdx, gdy);
      c.scale(gs);
    }

    void toChild(Canvas c) {
      c.translate(cdx, cdy);
      c.scale(cs);
    }

    final target = await _renderAlpha(n, n, (c) {
      toGlyph(c);
      fill.paint(c, const Offset(1, 1));
    });
    final wideOutline = glyph(Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 / gs
      ..strokeJoin = StrokeJoin.round);
    final targetWide = await _renderAlpha(n, n, (c) {
      toGlyph(c);
      fill.paint(c, const Offset(1, 1));
      wideOutline.paint(c, const Offset(1, 1));
    });
    final childThin = await _renderAlpha(n, n, (c) {
      toChild(c);
      _paintStrokes(c, _strokes, Colors.black, 5 / cs);
    });
    final childWide = await _renderAlpha(n, n, (c) {
      toChild(c);
      _paintStrokes(c, _strokes, Colors.black, 16 / cs);
    });

    var ink = 0, inkNear = 0, tgt = 0, tgtCovered = 0;
    for (var i = 3; i < n * n * 4; i += 4) {
      if (childThin[i] > 50) {
        ink++;
        if (targetWide[i] > 50) inkNear++;
      }
      if (target[i] > 100) {
        tgt++;
        if (childWide[i] > 50) tgtCovered++;
      }
    }
    if (ink == 0 || tgt == 0) return 0;
    final p = inkNear / ink, rc = tgtCovered / tgt;
    return (p + rc) == 0 ? 0 : 2 * p * rc / (p + rc);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_letter == null || _items.isEmpty) {
      return const Scaffold(backgroundColor: AppColors.bg);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: switch (_phase) {
          _Phase.work => _workView(),
          _Phase.celebrate => _celebrateView(),
          _Phase.finished => _finishedView(),
        },
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: AppTheme.minTap.toDouble(),
            height: AppTheme.minTap.toDouble(),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  size: 32, color: AppColors.ink),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Text('Write ',
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
          Text(_letter!,
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(
                  size: 30,
                  color: AppColors.highlight,
                  weight: FontWeight.w800)),
          const Spacer(),
          _progressDots(),
        ],
      ),
    );
  }

  Widget _progressDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _items.length; i++)
          GestureDetector(
            onTap: _busy ? null : () => _startItem(i),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: _done.contains(i)
                    ? AppColors.good
                    : (i == _index ? AppColors.accent : AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _jujuRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Juju(
              pose: _pose,
              size: 84,
              motion: _busy ? JujuMotion.wiggle : JujuMotion.bounce),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_message,
                        style: AppTheme.english(
                            size: 16, weight: FontWeight.w700)),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppColors.good),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelCard() {
    final it = _item;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          if (!it.isLetter) _sticker(it, 56),
          if (!it.isLetter) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  it.display,
                  textDirection: TextDirection.rtl,
                  style: AppTheme.arabic(
                      size: it.isLetter ? 40 : 32,
                      color: it.isLetter ? AppColors.highlight : AppColors.ink,
                      weight: FontWeight.w800),
                ),
                Text(it.english,
                    style: AppTheme.english(
                        size: 14,
                        color: AppColors.muted,
                        weight: FontWeight.w600)),
              ],
            ),
          ),
          _roundButton(
              emoji: '🔊',
              onTap: _listen,
              color: AppColors.accent,
              shadow: AppColors.accentShadow),
        ],
      ),
    );
  }

  Widget _stepChips() {
    Widget chip(String label, bool on) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.good : AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: AppTheme.english(
                  size: 14,
                  color: on ? Colors.white : AppColors.muted,
                  weight: FontWeight.w800)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          chip('1  Trace', _mode == _Mode.trace),
          const SizedBox(width: 8),
          chip('2  Write', _mode == _Mode.write),
          const Spacer(),
          if (_mode == _Mode.write)
            GestureDetector(
              onTap: () => setState(() => _showHint = !_showHint),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _showHint ? AppColors.tip : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                child: Text(_showHint ? '🙈 Hide help' : '💡 Help',
                    style: AppTheme.english(size: 14, weight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: LayoutBuilder(builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            _canvasSize = size;
            return ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Container(
                decoration: BoxDecoration(
                  color: _mode == _Mode.trace
                      ? AppColors.surface2
                      : AppColors.surface,
                  border: Border.all(color: AppColors.line, width: 3),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _addPoint(e.localPosition, start: true),
                  onPointerMove: (e) => _addPoint(e.localPosition),
                  child: CustomPaint(
                    size: size,
                    painter: _WritePainter(
                      repaint: _tick,
                      strokes: _strokes,
                      guide: _Guide.layout(size, _item.plain),
                      showGuide: _mode == _Mode.trace || _showHint,
                      faintGuide: _mode == _Mode.write,
                      showLines: _mode == _Mode.write,
                      inkColor: _mode == _Mode.trace
                          ? AppColors.highlight
                          : AppColors.ink,
                      brush: _mode == _Mode.trace ? _traceBrush : _writeBrush,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _bottomButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: _pillButton(
              label: '↺ Again',
              color: AppColors.surface,
              shadow: AppColors.line,
              textColor: AppColors.ink,
              onTap: _busy ? null : _clear,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _pillButton(
              label: "✅ I'm done",
              color: AppColors.good,
              shadow: AppColors.goodShadow,
              textColor: Colors.white,
              onTap: _busy ? null : _onDone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _workView() {
    return Column(
      children: [
        _topBar(),
        _jujuRow(),
        _modelCard(),
        _stepChips(),
        Expanded(child: _canvas()),
        _bottomButtons(),
      ],
    );
  }

  Widget _celebrateView() {
    final png = _lastPng;
    final it = _item;
    return LayoutBuilder(builder: (context, c) {
      final s =
          math.min(c.maxWidth * 0.86, c.maxHeight * 0.52).clamp(200.0, 380.0);
      final rect = _boardRects[_lastBoard] ?? _boardRects[1]!;
      final pose = switch (_lastBoard) {
        2 => JujuPose.board2,
        3 => JujuPose.board3,
        _ => JujuPose.board1,
      };
      return Column(
        children: [
          _topBar(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_message,
                textAlign: TextAlign.center,
                style: AppTheme.english(size: 20, weight: FontWeight.w800)),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: s + 40,
                height: s,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                        left: 20, top: 0, child: Juju(pose: pose, size: s)),
                    if (png != null)
                      Positioned(
                        left: 20 + rect.left * s,
                        top: rect.top * s,
                        width: rect.width * s,
                        height: rect.height * s,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.memory(png, fit: BoxFit.contain)
                              .animate()
                              .fadeIn(duration: 500.ms, delay: 300.ms)
                              .scale(
                                  begin: const Offset(0.5, 0.5),
                                  curve: Curves.easeOutBack),
                        ),
                      ),
                    if (!it.isLetter)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: _sticker(it, s * 0.30)
                            .animate(onPlay: (ctl) => ctl.repeat(reverse: true))
                            .moveY(
                                begin: 0,
                                end: -14,
                                duration: 650.ms,
                                curve: Curves.easeInOut)
                            .then()
                            .rotate(begin: -0.02, end: 0.02, duration: 400.ms),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Text(it.display,
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(size: 36, weight: FontWeight.w800)),
          Text('+1 ⭐',
                  style: AppTheme.english(
                      size: 18,
                      color: AppColors.accentShadow,
                      weight: FontWeight.w800))
              .animate()
              .scale(
                  begin: const Offset(0.4, 0.4),
                  duration: 500.ms,
                  curve: Curves.elasticOut),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _pillButton(
                    label: '🔊 Listen',
                    color: AppColors.accent,
                    shadow: AppColors.accentShadow,
                    textColor: AppColors.ink,
                    onTap: _listen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _pillButton(
                    label:
                        _done.length >= _items.length ? 'Finish ⭐' : 'Next ➜',
                    color: AppColors.good,
                    shadow: AppColors.goodShadow,
                    textColor: Colors.white,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _finishedView() {
    return Column(
      children: [
        _topBar(),
        const Spacer(),
        Juju(pose: JujuPose.gradCap, size: 200, motion: JujuMotion.pop),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'You wrote ${_letter!} and ${_items.length - 1} words!',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 24, weight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        Text('+2 ⭐',
                style: AppTheme.english(
                    size: 22,
                    color: AppColors.accentShadow,
                    weight: FontWeight.w800))
            .animate()
            .scale(
                begin: const Offset(0.3, 0.3),
                duration: 700.ms,
                curve: Curves.elasticOut),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _pillButton(
            label: '🧱 My writing wall',
            color: AppColors.blue,
            shadow: AppColors.ink,
            textColor: Colors.white,
            onTap: () => Navigator.pushNamed(context, Routes.writingWall),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _pillButton(
            label: '📖 Back to my letter',
            color: AppColors.accent,
            shadow: AppColors.accentShadow,
            textColor: AppColors.ink,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- small widgets

  Widget _sticker(_WriteItem it, double size) {
    final path = it.stickerPath;
    final fallback = Center(
      child: Text(it.emoji ?? '⭐', style: TextStyle(fontSize: size * 0.7)),
    );
    return SizedBox(
      width: size,
      height: size,
      child: path == null
          ? fallback
          : Image.asset(path,
              fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
    );
  }

  // Same idea as Screen 5: FittedBox so labels never get cut off.
  Widget _pillButton({
    required String label,
    required Color color,
    required Color shadow,
    required Color textColor,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 68,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: color == AppColors.surface
                ? Border.all(color: AppColors.line, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                  color: shadow,
                  offset: Offset(0, AppTheme.shadowDepth.toDouble()))
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style: AppTheme.english(
                    size: 20, color: textColor, weight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    required String emoji,
    required VoidCallback onTap,
    required Color color,
    required Color shadow,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppTheme.minTap.toDouble(),
        height: AppTheme.minTap.toDouble(),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 5))],
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guide shape (the grey letter/word to trace) – same layout for painting and scoring
// ---------------------------------------------------------------------------

class _Guide {
  _Guide(this.text, this.fontSize, this.offset);
  final String text;
  final double fontSize;
  final Offset offset;

  static TextStyle _style(double fs, {Paint? fg}) => GoogleFonts.balooBhaijaan2(
        fontSize: fs,
        fontWeight: FontWeight.w800,
        foreground: fg,
      );

  static TextPainter _painter(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout();

  static final Map<String, _Guide> _cache = {};

  static _Guide layout(Size size, String text) {
    final key =
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}|$text';
    final hit = _cache[key];
    if (hit != null) return hit;

    final single = text.runes.length == 1;
    var fs = size.height * (single ? 0.62 : 0.42);
    var tp = _painter(text, _style(fs));
    final maxW = size.width * 0.86, maxH = size.height * 0.96;
    final k = math.min(1.0, math.min(maxW / tp.width, maxH / tp.height));
    if (k < 1.0) {
      fs *= k;
      tp = _painter(text, _style(fs));
    }
    final g = _Guide(text, fs,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    if (_cache.length > 40) _cache.clear();
    _cache[key] = g;
    return g;
  }

  void paintFill(Canvas c, Color color) =>
      _painter(text, _style(fontSize, fg: Paint()..color = color))
          .paint(c, offset);

  void paintStroke(Canvas c, Color color, double width) => _painter(
        text,
        _style(fontSize,
            fg: Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeJoin = StrokeJoin.round),
      ).paint(c, offset);
}

void _paintStrokes(
    Canvas c, List<List<Offset>> strokes, Color color, double width) {
  final line = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  final dot = Paint()..color = color;
  for (final s in strokes) {
    if (s.isEmpty) continue;
    if (s.length == 1) {
      c.drawCircle(s.first, width / 2, dot);
      continue;
    }
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final p in s.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    c.drawPath(path, line);
  }
}

class _WritePainter extends CustomPainter {
  _WritePainter({
    required Listenable repaint,
    required this.strokes,
    required this.guide,
    required this.showGuide,
    required this.faintGuide,
    required this.showLines,
    required this.inkColor,
    required this.brush,
  }) : super(repaint: repaint);

  final List<List<Offset>> strokes;
  final _Guide guide;
  final bool showGuide, faintGuide, showLines;
  final Color inkColor;
  final double brush;

  @override
  void paint(Canvas canvas, Size size) {
    if (showLines) {
      // two soft writing lines, dashed
      final p = Paint()
        ..color = AppColors.line
        ..strokeWidth = 2.5;
      for (final y in [size.height * 0.35, size.height * 0.68]) {
        for (var x = 16.0; x < size.width - 16; x += 18) {
          canvas.drawLine(
              Offset(x, y), Offset(math.min(x + 10, size.width - 16), y), p);
        }
      }
    }
    if (showGuide) {
      final a = faintGuide ? 0.10 : 0.20;
      guide.paintFill(canvas, AppColors.muted.withValues(alpha: a));
      guide.paintStroke(canvas,
          AppColors.muted.withValues(alpha: faintGuide ? 0.25 : 0.55), 2.5);
    }
    _paintStrokes(canvas, strokes, inkColor, brush);
  }

  @override
  bool shouldRepaint(covariant _WritePainter old) => true;
}
