// Playdough Magic – WRITING. Juju shows a dotless letter body (e.g. the boat shape
// shared by ب ت ث). The child makes it from playdough (or draws it with a finger),
// snaps it, Muse Spark checks the shape and finds where it is, then the APP adds the
// magic dots on the child's own shape: 1 below = ب, 2 above = ت, 3 above = ث.
// Families live in assets/data/magic_world.json ("letter_families").
// Magic view = under the sea: fish swim by, the dots arrive as bubbles, then the
// letter shows how it changes shape (alone / start / middle / end) with a word each.
//
// Kid-first layout: Juju speaks the instructions, so the screen shows pictures,
// not sentences. The shape-change chips show the letter shapes themselves
// (بـ ـبـ ـب) instead of English words.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/audio_index.dart';
import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/meta_games.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/juju.dart';
import '../../widgets/loading_match.dart';
import 'magic_common.dart';

enum _Phase { make, draw, magic, retry }

class PlaydoughScreen extends StatefulWidget {
  const PlaydoughScreen({super.key});
  @override
  State<PlaydoughScreen> createState() => _PlaydoughScreenState();
}

class _PlaydoughScreenState extends State<PlaydoughScreen> {
  List<Map<String, dynamic>> _families = [];
  Map<String, dynamic>? _family;
  _Phase _phase = _Phase.make;
  final _pad = DrawPadController()..width = 18;
  Uint8List? _image; // in memory only
  double _aspect = 1;
  Rect _box = const Rect.fromLTWH(0.25, 0.35, 0.5, 0.3);
  int _member = 0;
  bool _rewarded = false;
  bool _showIntro = true; // short pop message on entry
  Map<String, dynamic> _positions = {}; // letter_positions.json
  int _form = 0; // 0 alone, 1 start, 2 middle, 3 end
  Timer? _formTimer;
  int _dive =
      0; // bumps each time a new shape jumps from the desert into the sea
  bool _landed =
      false; // dots only come once the shape has settled in the water

  List<Map<String, dynamic>> get _members =>
      ((_family?['members'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  @override
  void initState() {
    super.initState();
    MagicData.load().then((d) {
      final fams = ((d['letter_families'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (fams.isEmpty) return;
      final current = ProgressService.instance.currentLetter;
      final fam = fams.firstWhere(
          (f) => [
                for (final m in (f['members'] as List? ?? const []))
                  str((m as Map)['letter'])
              ].contains(current),
          orElse: () => fams.first);
      setState(() {
        _families = fams;
        _family = fam;
        _showIntro = true;
      });
      playJuju('playdough_make');
      // auto-dismiss the pop message so the desert stays clean
      Timer(const Duration(seconds: 4), () {
        if (mounted && _showIntro && _phase == _Phase.make) {
          setState(() => _showIntro = false);
        }
      });
    });
    rootBundle.loadString('assets/data/letter_positions.json').then((t) {
      if (mounted) {
        setState(
            () => _positions = (jsonDecode(t) as Map).cast<String, dynamic>());
      }
    }).catchError(
        (_) {}); // no file -> the shapes still show, just without words
  }

  @override
  void dispose() {
    _formTimer?.cancel();
    _pad.dispose();
    super.dispose();
  }

  Future<void> _check(Uint8List image, {required bool isDrawing}) async {
    final fam = _family;
    if (fam == null) return;
    final res = await waitWithMatch(
        context,
        MetaGames.instance.shapeCheck(image, str(fam['shape_description']),
            isDrawing: isDrawing),
        message: "I'm looking at your shape…");
    if (!mounted) return;
    final decoded = await decodeImageFromList(image);
    if (!mounted) return;
    setState(() {
      _image = image;
      _aspect = decoded.width / decoded.height;
    });
    if (res != null && !res.looksRight) {
      setState(() => _phase = _Phase.retry);
      AudioService.instance.playAsset('juju/juju_en_great_trying.mp3');
      return;
    }
    // looks right, or couldn't check → celebrate anyway
    setState(() {
      _box = res?.box ?? _box;
      _phase = _Phase.magic;
      _member = 0;
      _dive++;
      _landed = MediaQuery.of(context).disableAnimations;
    });
    if (!_rewarded) {
      ProgressService.instance.addStars(2);
      _rewarded = true;
    }
    _pickMember(0);
  }

  Future<void> _snap() async {
    final photo = await snapPhoto();
    if (photo != null && mounted) await _check(photo, isDrawing: false);
  }

  Future<void> _checkDrawing() async {
    if (_pad.isEmpty) return;
    final png = await _pad.toPng();
    if (png != null && mounted) await _check(png, isDrawing: true);
  }

  void _pickMember(int i) {
    if (i >= _members.length) return;
    setState(() {
      _member = i;
      _form = 0;
    });
    AudioIndex.instance.playLetter(str(_members[i]['letter']), withSound: true);
    // after the bubbles land, the letter starts changing shape on its own
    _formTimer?.cancel();
    // wait for the dive + the big bubbles before the letter starts changing shape
    _formTimer = Timer(Duration(milliseconds: _landed ? 2600 : 4600), () {
      _formTimer = Timer.periodic(const Duration(milliseconds: 1700), (_) {
        if (mounted) setState(() => _form = (_form + 1) % 4);
      });
    });
  }

  void _tapForm(int i) {
    _formTimer?.cancel(); // child took over
    setState(() => _form = i);
    final ex = _example(_letterNow, i);
    if (ex.word != null) {
      playWord(ex.word!);
    } else {
      AudioIndex.instance.playLetter(_letterNow, withSound: false);
    }
  }

  String get _letterNow =>
      _members.isEmpty ? '' : str(_members[_member]['letter']);

  static const _nonJoining = {'ا', 'د', 'ذ', 'ر', 'ز', 'و'};
  static const _formNames = ['Alone', 'Start', 'Middle', 'End'];

  /// The 4 shapes, built with the joining stroke (ـ). Non-joining letters (د ذ ر ز ا و)
  /// never join the next letter, so their start looks like alone, middle like end.
  String _shape(String l, int f) {
    final joins = !_nonJoining.contains(l);
    return switch (f) {
      1 => joins ? '${l}ـ' : l,
      2 => joins ? 'ـ${l}ـ' : 'ـ${l}',
      3 => 'ـ${l}',
      _ => l,
    };
  }

  /// Example word for a shape: alone -> the letter's hunt word; others -> letter_positions.json.
  ({String arabic, String english, HuntWord? word}) _example(String l, int f) {
    if (f == 0) {
      final ws = Repository.instance.huntWordsForLetter(l);
      if (ws.isEmpty) return (arabic: '', english: '', word: null);
      final w = ws.first;
      return (arabic: str(w.arabicWord), english: str(w.englishWord), word: w);
    }
    final key = const ['', 'beginning', 'middle', 'end'][f];
    final entry = _positions[l];
    final positions = entry is Map ? entry['positions'] : null;
    final list = positions is Map ? positions[key] : null;
    if (list is! List || list.isEmpty) {
      return (arabic: '', english: '', word: null);
    }
    final raw = str(list.first); // e.g. "تِلْفَاز (Television)"
    final cut = raw.indexOf(' (');
    final ar = cut < 0 ? raw : raw.substring(0, cut);
    final en = cut < 0 ? '' : raw.substring(cut + 2).replaceAll(')', '');
    return (
      arabic: ar,
      english: en,
      word: en.isEmpty ? null : huntWordByEnglish(en)
    );
  }

  void _selectFamily(Map<String, dynamic> f) {
    if (identical(f, _family)) return;
    _formTimer?.cancel();
    _pad.clear();
    setState(() {
      _family = f;
      _phase = _Phase.make;
      _image = null;
      _member = 0;
      _rewarded = false;
      _showIntro = false;
    });
    final ms = (f['members'] as List?) ?? const [];
    final first = ms.isEmpty ? null : ms.first;
    if (first is Map) {
      AudioIndex.instance.playLetter(str(first['letter']), withSound: false);
    }
  }

  /// One chip per letter family, showing its members (e.g. ب ت ث).
  Widget _familyPicker() {
    return SizedBox(
      height: 64,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _families.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _families[i];
            final sel = identical(f, _family);
            final letters = [
              for (final m in (f['members'] as List? ?? const []))
                str((m as Map)['letter'])
            ].join(' ');
            return Semantics(
              button: true,
              selected: sel,
              label: 'Letter family $letters',
              child: GestureDetector(
                onTap: () => _selectFamily(f),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: sel ? AppColors.accentShadow : AppColors.line,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Center(child: arabicLine(letters, size: 26)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _restart() {
    _formTimer?.cancel();
    _pad.clear();
    setState(() {
      _phase = _Phase.make;
      _image = null;
      _rewarded = false;
      _showIntro = false;
    });
    playJuju('playdough_make');
  }

  @override
  Widget build(BuildContext context) {
    return MagicScaffold(
      title: 'Playdough Magic',
      child: _family == null
          ? const Center(child: CircularProgressIndicator())
          : switch (_phase) {
              _Phase.make => _makeView(),
              _Phase.draw => _drawView(),
              _Phase.magic => _magicView(),
              _Phase.retry => _retryView(),
            },
    );
  }

  Widget _body({double size = 180}) {
    final fam = _family!;
    if (str(fam['body']) == 'boat') {
      return CustomPaint(size: Size(size, size * 0.6), painter: _BoatPainter());
    }
    return arabicLine(str(fam['body_text']), size: size * 0.7);
  }

  /// Small one-line bubble (Juju says the full instruction out loud).
  Widget _miniBubble(String text) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.elasticOut,
      builder: (_, v, c) => Transform.scale(
        scale: v <= 0 ? 0.01 : v,
        alignment: Alignment.topLeft,
        child: c,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8C37A), width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), offset: Offset(0, 4))
          ],
        ),
        child: Text(text,
            style: AppTheme.english(size: 16, weight: FontWeight.w800)),
      ),
    );
  }

  Widget _makeView() {
    return Column(children: [
      _familyPicker(),
      const SizedBox(height: 12),
      // Desert card: Juju next to the shape to copy. Instructions are spoken.
      Expanded(
        child: _DesertStage(
          child: Stack(children: [
            // the shape to copy: a compact card, not a full-height panel
            Align(
              alignment: const Alignment(0.45, -0.2),
              child: FractionallySizedBox(
                widthFactor: 0.62,
                child: AspectRatio(
                  aspectRatio: 1.15,
                  child: _ShapePop(
                    tail: true,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: _body(size: 140),
                    ),
                  ),
                ),
              ),
            ),
            // Juju bottom-left, "talking" to the card through its tail
            Positioned(
              left: -6,
              bottom: -4,
              child: Juju(pose: JujuPose.pencil, size: 150),
            ),
            if (_showIntro)
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _showIntro = false),
                  child: _miniBubble('Make this shape!'),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: RoundIcon(
                icon: Icons.volume_up_rounded,
                label: 'Hear Juju again',
                size: 48,
                onTap: () => playJuju('playdough_make'),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      // Snap (main) + draw (small alternative), on one row
      Row(children: [
        Expanded(
          child: GameButton(
              label: 'Snap it!',
              icon: Icons.photo_camera_rounded,
              onTap: _snap),
        ),
        const SizedBox(width: 12),
        RoundIcon(
          icon: Icons.gesture_rounded,
          label: 'No playdough? Draw it with your finger',
          size: 72,
          onTap: () => setState(() => _phase = _Phase.draw),
        ),
      ]),
    ]);
  }

  Widget _drawView() {
    return Column(children: [
      Row(children: [
        Opacity(opacity: 0.35, child: _body(size: 90)),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Draw it!',
              style: AppTheme.english(size: 22, weight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8C37A), width: 3),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: DrawPad(controller: _pad),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        RoundIcon(
            icon: Icons.undo_rounded,
            label: 'Undo',
            onTap: _pad.undo,
            size: 64),
        const SizedBox(width: 10),
        RoundIcon(
            icon: Icons.delete_outline_rounded,
            label: 'Clear',
            onTap: _pad.clear,
            size: 64),
        const SizedBox(width: 12),
        Expanded(
            child: GameButton(
                label: 'Done!',
                icon: Icons.check_rounded,
                onTap: _checkDrawing)),
      ]),
    ]);
  }

  Widget _retryView() {
    return Column(children: [
      const JujuSays(
        pose: JujuPose.encourage,
        size: 76,
        text: 'Almost! Try again.',
        sub: 'Look at the shape.',
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Row(children: [
          Expanded(child: _imageView(showDots: false)),
          const SizedBox(width: 12),
          Expanded(
            child: _DesertStage(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.15,
                  child: _ShapePop(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: _body(size: 110),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      GameButton(
          label: 'Try again', icon: Icons.refresh_rounded, onTap: _restart),
    ]);
  }

  Widget _magicView() {
    return Column(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: LayoutBuilder(builder: (context, oc) {
            final wy = oc.maxHeight * _water; // where the desert meets the sea
            return TweenAnimationBuilder<double>(
              key: ValueKey('dive-$_dive'),
              tween: Tween(begin: _landed ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 1800),
              onEnd: () {
                if (mounted && !_landed) setState(() => _landed = true);
              },
              builder: (context, v, _) => Stack(children: [
                const Positioned.fill(child: _OceanBackground()),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, wy + 10, 14, 12),
                  child: Column(children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Center(
                          child: _diving(
                            v,
                            // from the card's centre up to the top of the dune
                            startDy: wy * 0.45 - (wy + 10 + c.maxHeight / 2),
                            // the child's shape stays a smallish card, so the
                            // sea, the bubbles and the letters get the space
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth: c.maxWidth * 0.5,
                                  maxHeight: c.maxHeight * 0.62),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x33000000),
                                        blurRadius: 14,
                                        offset: Offset(0, 8))
                                  ],
                                ),
                                child: _imageView(showDots: true),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < _members.length; i++) ...[
                        if (i > 0) const SizedBox(width: 14),
                        _memberButton(i),
                      ],
                    ]),
                  ]),
                ),
                if (v > 0.5 && v < 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: wy - 40,
                    height: 80,
                    child: IgnorePointer(
                        child: CustomPaint(
                            painter: _SplashPainter((v - 0.5) / 0.5))),
                  ),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(height: 10),
      _formsCard(),
      const SizedBox(height: 10),
      GameButton(
          label: 'Make another',
          icon: Icons.refresh_rounded,
          onTap: _restart,
          height: 60),
    ]);
  }

  /// The child's shape sits on the dune, wiggles, hops, splashes into the sea and
  /// sinks to the middle. v runs 0 → 1 over 1.8 s.
  Widget _diving(double v, {required double startDy, required Widget child}) {
    double dy, scale, rot;
    if (v < 0.25) {
      // on the sand, excited wiggle
      dy = startDy;
      scale = 0.3;
      rot = sin(v * 48) * 0.1;
    } else if (v < 0.5) {
      // hop up and over the waterline
      final p = (v - 0.25) / 0.25;
      dy = startDy + (startDy * -0.55) * p - sin(p * pi) * 46;
      scale = 0.3 + 0.25 * p;
      rot = -0.3 * p;
    } else {
      // splash, sink and settle with a little bounce
      final e = Curves.easeOutBack.transform((v - 0.5) / 0.5);
      dy = startDy * 0.45 * (1 - e);
      scale = 0.55 + 0.45 * e;
      rot = -0.3 + 0.26 * e;
    }
    return Transform.translate(
      offset: Offset(0, dy),
      child: Transform.rotate(
          angle: rot, child: Transform.scale(scale: scale, child: child)),
    );
  }

  /// "Watch it change": a big shape that morphs alone → start → middle → end,
  /// four chips that SHOW the shapes (no words), and a picture word for the
  /// shape on show. Tap anything to hear it.
  Widget _formsCard() {
    final l = _letterNow;
    final ex = _example(l, _form);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => _tapForm(_form),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Container(
              key: ValueKey('$l-$_form'),
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                    colors: [Color(0xFFE4F7FF), Color(0xFF9FDDF5)]),
              ),
              child: Center(child: arabicLine(_shape(l, _form), size: 46)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Directionality(
                  textDirection:
                      TextDirection.rtl, // Arabic order: alone on the right
                  child: Row(children: [
                    for (var f = 0; f < 4; f++) ...[
                      if (f > 0) const SizedBox(width: 5),
                      Expanded(child: _formChip(f)),
                    ],
                  ]),
                ),
                const SizedBox(height: 6),
                // picture + Arabic word (the English stays for screen readers)
                SizedBox(
                  height: 42,
                  child: ex.arabic.isEmpty
                      ? const SizedBox()
                      : Semantics(
                          button: true,
                          label: '${ex.arabic}, ${ex.english}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => _tapForm(_form),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (ex.word != null)
                                    StickerImage(str(ex.word!.sticker),
                                        size: 40),
                                  const SizedBox(width: 8),
                                  Flexible(
                                      child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child:
                                              arabicLine(ex.arabic, size: 26))),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.volume_up_rounded,
                                      size: 20, color: AppColors.blue),
                                ]),
                          ),
                        ),
                ),
              ]),
        ),
      ]),
    );
  }

  /// A chip shows the letter shape itself (ب / بـ / ـبـ / ـب), not a word.
  Widget _formChip(int f) {
    final sel = f == _form;
    return Semantics(
      button: true,
      selected: sel,
      label: '${_formNames[f]} shape',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _tapForm(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 50,
          decoration: BoxDecoration(
            color: sel ? AppColors.blue : AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: arabicLine(_shape(_letterNow, f),
                  size: 24, color: sel ? Colors.white : AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }

  /// Letter choices float in the sea as bubbles.
  Widget _memberButton(int i) {
    final sel = i == _member;
    return Semantics(
      button: true,
      selected: sel,
      label: 'Letter ${str(_members[i]['letter'])}',
      child: GestureDetector(
        onTap: () => _pickMember(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: sel ? 76 : 66,
          height: sel ? 76 : 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sel ? AppColors.accent : const Color(0xCCFFFFFF),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: sel ? AppColors.accentShadow : const Color(0x33000000),
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Center(
              child: arabicLine(str(_members[i]['letter']),
                  size: sel ? 38 : 32, color: AppColors.ink)),
        ),
      ),
    );
  }

  Widget _imageView({required bool showDots}) {
    final img = _image;
    if (img == null) return const SizedBox();
    final m = _members.isEmpty ? null : _members[_member];
    return AspectRatio(
      aspectRatio: _aspect,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(img, fit: BoxFit.fill),
            ),
          ),
          if (showDots && _landed && m != null)
            ..._dots(c.maxWidth, c.maxHeight, (m['dots'] as num?)?.toInt() ?? 0,
                str(m['where'])),
        ]);
      }),
    );
  }

  List<Widget> _dots(double w, double h, int count, String where) {
    if (count <= 0) return const [];
    final r = max(
        w * 0.075, 10.0); // dot radius - big enough to see from arm's length
    final gap = h * 0.1;
    final cx = _box.center.dx * w;
    final base = switch (where) {
      'below' => (_box.bottom * h + gap).clamp(r, h - r).toDouble(),
      'inside' =>
        (_box.top * h + _box.height * h * 0.62).clamp(r, h - r).toDouble(),
      _ => (_box.top * h - gap).clamp(r, h - r).toDouble(),
    };
    final points = <Offset>[
      if (count == 1) Offset(cx, base),
      if (count == 2) ...[
        Offset(cx - r * 1.4, base),
        Offset(cx + r * 1.4, base)
      ],
      if (count >= 3) ...[
        Offset(cx - r * 1.4, base),
        Offset(cx + r * 1.4, base),
        Offset(cx, base - r * 2.4),
      ],
    ];
    final box = r * 7; // room for the big bubble and its pop ring
    // One big bubble per dot floats up from the seabed, wobbling, parks on its spot
    // and pops - leaving the dot behind.
    return [
      for (var i = 0; i < points.length; i++)
        Positioned(
          key: ValueKey('$_dive-$_member-$i'),
          left: points[i].dx - box / 2,
          top: points[i].dy - box / 2,
          width: box,
          height: box,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 2000 + i * 500),
            builder: (_, v, __) {
              final total = 2000 + i * 500;
              final delay = i * 500 / total;
              final t = ((v - delay) / (1 - delay)).clamp(0.0, 1.0);
              if (t <= 0) return const SizedBox();
              final rise =
                  Curves.easeOutCubic.transform((t / 0.72).clamp(0.0, 1.0));
              final dy =
                  (1 - rise) * (h - points[i].dy + 220); // starts on the seabed
              final wobble = sin(t * pi * 6) * r * 0.8 * (1 - rise);
              if (t < 0.72) {
                final d = r *
                    (5.2 -
                        1.6 * rise); // big, then a little smaller as it arrives
                return Transform.translate(
                  offset: Offset(wobble, dy),
                  child: Center(
                    child: Transform.scale(
                      scaleX: 1 + sin(t * pi * 10) * 0.06,
                      scaleY: 1 - sin(t * pi * 10) * 0.06,
                      child: Container(
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            center: Alignment(-0.35, -0.35),
                            colors: [
                              Color(0xCCFFFFFF),
                              Color(0x55BFEFFF),
                              Color(0x33BFEFFF)
                            ],
                            stops: [0, 0.45, 1],
                          ),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x332A8FC0), blurRadius: 8)
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              // pop!
              final p = (t - 0.72) / 0.28;
              return Stack(alignment: Alignment.center, children: [
                Opacity(
                  opacity: (1 - p).clamp(0.0, 1.0),
                  child: Container(
                    width: r * (3.6 + 3 * p),
                    height: r * (3.6 + 3 * p),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 4 * (1 - p) + 1),
                    ),
                  ),
                ),
                for (var k = 0; k < 6; k++)
                  Transform.translate(
                    offset: Offset(cos(k * pi / 3) * r * (1.8 + 2 * p),
                        sin(k * pi / 3) * r * (1.8 + 2 * p)),
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Container(
                          width: r * 0.5,
                          height: r * 0.5,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.white)),
                    ),
                  ),
                Transform.scale(
                  scale: Curves.elasticOut.transform(p.clamp(0.0, 1.0)),
                  child: Container(
                    width: r * 2,
                    height: r * 2,
                    decoration: BoxDecoration(
                      color: AppColors.highlight,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 6,
                            offset: Offset(0, 3))
                      ],
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
    ];
  }
}

/// The white shape card as a pop-in speech bubble: elastic scale-in, with an
/// optional tail at the bottom-left pointing down at Juju. It fills whatever
/// size its parent gives it (wrap it in AspectRatio / SizedBox).
class _ShapePop extends StatelessWidget {
  final Widget child;
  final bool tail;
  const _ShapePop({required this.child, this.tail = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (_, v, c) => Transform.scale(
        scale: v <= 0 ? 0.01 : v,
        alignment: Alignment.bottomLeft,
        child: c,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: _cardEdge, width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), offset: Offset(0, 5))
                ],
              ),
              child: child,
            ),
          ),
          if (tail)
            const Positioned(
              left: 22,
              bottom: -19,
              width: 30,
              height: 22,
              child: CustomPaint(painter: _TailPainter()),
            ),
        ],
      ),
    );
  }
}

const _cardEdge = Color(0xFFE8C37A);

/// Speech-bubble tail pointing down-left, joined to the card's bottom edge.
class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final tip = Offset(0, s.height);
    final a = Offset(6, -3); // just inside the card, hides its border
    final b = Offset(s.width, -3);
    canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(tip.dx, tip.dy)
          ..close(),
        Paint()..color = Colors.white);
    final edge = Paint()
      ..color = _cardEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(a.dx, 0), tip, edge);
    canvas.drawLine(Offset(b.dx, 0), tip, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Same desert card as Detective / Feed Juju: cream sky, sun, two dunes.
/// The white shape card sits on top of it so Playdough matches the other games.
class _DesertStage extends StatelessWidget {
  final Widget child;
  const _DesertStage({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: CustomPaint(
          painter: _MiniDesertPainter(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MiniDesertPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFF6DB));
    // sun
    canvas.drawCircle(Offset(s.width * 0.84, s.height * 0.20), 26,
        Paint()..color = const Color(0xFFFFD666));
    // back dune
    canvas.drawPath(
        Path()
          ..moveTo(0, s.height * 0.42)
          ..quadraticBezierTo(
              s.width * 0.25, s.height * 0.28, s.width * 0.55, s.height * 0.42)
          ..quadraticBezierTo(
              s.width * 0.8, s.height * 0.52, s.width, s.height * 0.38)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = const Color(0xFFF9E2A8));
    // front dune
    canvas.drawPath(
        Path()
          ..moveTo(0, s.height * 0.62)
          ..quadraticBezierTo(
              s.width * 0.35, s.height * 0.48, s.width * 0.65, s.height * 0.62)
          ..quadraticBezierTo(
              s.width * 0.85, s.height * 0.70, s.width, s.height * 0.62)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = const Color(0xFFF5C87A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fraction of the scene's height that is desert, above the waterline.
const double _water = 0.17;

/// Water ring + droplets where the shape splashes in. p runs 0 → 1.
class _SplashPainter extends CustomPainter {
  final double p;
  _SplashPainter(this.p);

  @override
  void paint(Canvas canvas, Size s) {
    if (p <= 0 || p >= 1) return;
    final c = Offset(s.width / 2, s.height / 2);
    final fade = 1 - p;
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 60 + 200 * p, height: 14 + 30 * p),
        Paint()
          ..color = Colors.white.withOpacity(0.9 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    final drop = Paint()..color = const Color(0xFFE4F7FF).withOpacity(fade);
    for (var k = 0; k < 7; k++) {
      final a = pi + pi * (k + 0.5) / 7; // fan upward
      final dist = 20 + 60 * p;
      final x = c.dx + cos(a) * dist * 1.4;
      final y = c.dy + sin(a) * dist + 70 * p * p; // up, then falling back
      canvas.drawCircle(Offset(x, y), 5 * fade + 2, drop);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) => old.p != p;
}

/// Under-the-sea background: light rays, swaying seaweed, fish swimming both ways
/// and rising bubbles. All drawn in code (no assets). Stops moving when the phone
/// asks for reduced motion.
class _OceanBackground extends StatefulWidget {
  const _OceanBackground();
  @override
  State<_OceanBackground> createState() => _OceanBackgroundState();
}

class _OceanBackgroundState extends State<_OceanBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 16));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _OceanPainter(_c.value)),
        ),
      );
}

class _Fish {
  final double y, size, speed, phase;
  final int dir; // 1 = swims right, -1 = swims left
  final Color body, fin;
  const _Fish(
      this.y, this.size, this.speed, this.phase, this.dir, this.body, this.fin);
}

class _OceanPainter extends CustomPainter {
  final double t; // 0..1, loops every 16 s
  _OceanPainter(this.t);

  static const _fish = [
    _Fish(0.10, 46, 1, 0.0, 1, Color(0xFFFF9F43), Color(0xFFE5732A)),
    _Fish(0.24, 32, 2, 0.4, -1, Color(0xFFFFD54A), Color(0xFFE0A800)),
    _Fish(0.40, 56, 1, 0.7, -1, Color(0xFFFF7EB6), Color(0xFFD9488A)),
    _Fish(0.52, 28, 2, 0.15, 1, Color(0xFF7BE0B0), Color(0xFF2FAE7C)),
    _Fish(0.64, 40, 1, 0.55, 1, Color(0xFFB79CFF), Color(0xFF7E5BE0)),
    _Fish(0.30, 26, 3, 0.85, 1, Color(0xFFFF6B6B), Color(0xFFC94545)),
    _Fish(0.76, 36, 2, 0.3, -1, Color(0xFF5EC8F2), Color(0xFF2A8FC0)),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final wy = s.height * _water;

    // desert sky, sun, dunes and a palm
    final sky = Rect.fromLTWH(0, 0, s.width, wy);
    canvas.drawRect(
        sky,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE2A6), Color(0xFFFFF3D6)],
          ).createShader(sky));
    canvas.drawCircle(Offset(s.width * 0.84, wy * 0.32), wy * 0.2,
        Paint()..color = const Color(0xFFFFC94A));
    canvas.drawPath(
        Path()
          ..moveTo(0, wy + 4)
          ..lineTo(0, wy * 0.62)
          ..quadraticBezierTo(
              s.width * 0.22, wy * 0.28, s.width * 0.5, wy * 0.62)
          ..quadraticBezierTo(s.width * 0.75, wy * 0.9, s.width, wy * 0.55)
          ..lineTo(s.width, wy + 4)
          ..close(),
        Paint()..color = const Color(0xFFF2C46F));
    canvas.drawPath(
        Path()
          ..moveTo(0, wy + 4)
          ..lineTo(0, wy * 0.85)
          ..quadraticBezierTo(s.width * 0.6, wy * 0.6, s.width, wy * 0.9)
          ..lineTo(s.width, wy + 4)
          ..close(),
        Paint()..color = const Color(0xFFE8B35A));
    final trunk = Paint()
      ..color = const Color(0xFF9A6A2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final palm = Offset(s.width * 0.1, wy * 0.6);
    canvas.drawLine(palm, palm.translate(6, -wy * 0.42), trunk);
    final leaf = Paint()..color = const Color(0xFF2FAE7C);
    final top = palm.translate(6, -wy * 0.42);
    for (var k = 0; k < 5; k++) {
      final a = -pi + k * pi / 4 + sin(t * 2 * pi * 2) * 0.05;
      canvas.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo(top.dx + cos(a) * 18, top.dy + sin(a) * 18 - 6,
                top.dx + cos(a) * 30, top.dy + sin(a) * 30 + 8)
            ..quadraticBezierTo(
                top.dx + cos(a) * 14, top.dy + sin(a) * 14, top.dx, top.dy)
            ..close(),
          leaf);
    }

    // the sea, with a moving wavy top edge
    final wave = Path()..moveTo(0, wy);
    final sea = Path()..moveTo(0, wy);
    for (var x = 0.0; x <= s.width; x += 6) {
      final y = wy + sin(x / 22 + t * 2 * pi * 3) * 4;
      wave.lineTo(x, y);
      sea.lineTo(x, y);
    }
    sea
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(
        sea,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8FE3F7), Color(0xFF3FA9DD), Color(0xFF1C6FB0)],
          ).createShader(Rect.fromLTWH(0, wy, s.width, s.height - wy)));
    canvas.drawPath(
        wave,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

    // soft light rays from the surface
    final ray = Paint()..color = const Color(0x22FFFFFF);
    for (var i = 0; i < 4; i++) {
      final x = s.width * (0.12 + 0.26 * i) + sin(t * 2 * pi + i) * 10;
      canvas.drawPath(
          Path()
            ..moveTo(x, wy)
            ..lineTo(x + 34, wy)
            ..lineTo(x + 90, s.height)
            ..lineTo(x + 30, s.height)
            ..close(),
          ray);
    }

    // sand + swaying seaweed
    canvas.drawPath(
        Path()
          ..moveTo(0, s.height)
          ..lineTo(0, s.height - 26)
          ..quadraticBezierTo(
              s.width * 0.3, s.height - 44, s.width * 0.55, s.height - 28)
          ..quadraticBezierTo(
              s.width * 0.8, s.height - 14, s.width, s.height - 34)
          ..lineTo(s.width, s.height)
          ..close(),
        Paint()..color = const Color(0xFFF3D99A));
    final weed = Paint()
      ..color = const Color(0xFF2FAE7C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final bx in [0.08, 0.16, 0.86, 0.93]) {
      final x = s.width * bx;
      final sway = sin(t * 2 * pi * 2 + bx * 10) * 12;
      canvas.drawPath(
          Path()
            ..moveTo(x, s.height - 20)
            ..quadraticBezierTo(
                x + sway, s.height - 70, x + sway * 0.4, s.height - 110),
          weed);
    }

    // fish
    for (final f in _fish) {
      final p = (t * f.speed + f.phase) % 1.0;
      final span = s.width + f.size * 3;
      final x = f.dir == 1
          ? -f.size * 1.5 + p * span
          : s.width + f.size * 1.5 - p * span;
      final y = wy +
          24 +
          (s.height - wy - 60) * f.y +
          sin((p * 6 + f.phase) * pi) * 8;
      _drawFish(canvas, Offset(x, y), f);
    }

    // rising bubbles
    final bubble = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 10; i++) {
      final p = (t * 3 + i * 0.137) % 1.0;
      final x = s.width * ((i * 0.31) % 1.0) + sin((p * 4 + i) * pi) * 6;
      canvas.drawCircle(
          Offset(x, s.height - (s.height - wy) * p), 3.0 + (i % 3) * 2, bubble);
    }
  }

  void _drawFish(Canvas canvas, Offset at, _Fish f) {
    final sz = f.size;
    final wag = sin(t * 2 * pi * 12 + f.phase * 10) * 0.25;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(f.dir.toDouble(), 1);
    canvas.drawPath(
        Path()
          ..moveTo(-sz * 0.4, 0)
          ..lineTo(-sz * 0.85, -sz * (0.32 + wag))
          ..lineTo(-sz * 0.85, sz * (0.32 - wag))
          ..close(),
        Paint()..color = f.fin);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: sz, height: sz * 0.66),
        Paint()..color = f.body);
    canvas.drawPath(
        Path()
          ..moveTo(-sz * 0.05, -sz * 0.3)
          ..quadraticBezierTo(sz * 0.05, -sz * 0.55, sz * 0.2, -sz * 0.28)
          ..close(),
        Paint()..color = f.fin);
    canvas.drawCircle(Offset(sz * 0.24, -sz * 0.06), sz * 0.11,
        Paint()..color = Colors.white);
    canvas.drawCircle(Offset(sz * 0.27, -sz * 0.06), sz * 0.055,
        Paint()..color = AppColors.ink);
    canvas.drawCircle(Offset(sz * 0.12, sz * 0.12), sz * 0.06,
        Paint()..color = const Color(0x55FF6B8A));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OceanPainter old) => old.t != t;
}

/// The dotless body shared by ب ت ث: a wide, shallow "boat" with raised ends.
class _BoatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.08
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(s.width * 0.06, s.height * 0.15)
      ..quadraticBezierTo(
          s.width * 0.02, s.height * 0.85, s.width * 0.5, s.height * 0.85)
      ..quadraticBezierTo(
          s.width * 0.98, s.height * 0.85, s.width * 0.94, s.height * 0.35);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
