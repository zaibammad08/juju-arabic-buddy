// Juju Detective – LISTENING. Juju says the mystery word in Arabic (e.g. كُرْسِي).
// The child works out what it is with 3 clues buried in the sand, dug up one at a time:
// (1) an English riddle (existing hint audio + text), (2) the Arabic first letter's
// sound, (3) the English first letter with blanks (C _ _ _ _). Then they snap it;
// Muse Spark checks the photo.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;

import '../../data/audio_index.dart';
import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/meta_games.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/juju.dart';
import '../../widgets/loading_match.dart';
import 'magic_common.dart';

enum _Phase { hunting, found, tryAgain, couldNotCheck }

/// Desert palette for the dune scene.
class _Sand {
  static const sky = Color(0xFFFFF4E0);
  static const sun = Color(0xFFFFD36E);
  static const duneBack = Color(0xFFF4D9A3);
  static const duneFront = Color(0xFFEBC584);
  static const ripple = Color(0xFFD9A95A);
  static const mound = Color(0xFFDDAF66);
  static const moundEdge = Color(0xFFC99A4E);
  static const moundText = Color(0xFF4A3214);
  static const card = Color(0xFFFFF8EA);
  static const cardBorder = Color(0xFFE2C893);
  static const parchment = Color(0xFFFFFDF7);
}

class DetectiveScreen extends StatefulWidget {
  const DetectiveScreen({super.key});
  @override
  State<DetectiveScreen> createState() => _DetectiveScreenState();
}

class _DetectiveScreenState extends State<DetectiveScreen> {
  final _rng = Random();
  HuntWord? _target;
  int _cluesOpen = 0; // 0..3
  _Phase _phase = _Phase.hunting;
  String _seen = '';
  String? _lastId;
  Map<String, String> _hints =
      {}; // id -> English riddle text (arabic_cache.json)

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/data/arabic_cache.json').then((t) {
      final list = jsonDecode(t);
      if (list is List && mounted) {
        setState(() => _hints = {
              for (final e in list)
                if (e is Map) str(e['id']): str(e['hint'])
            });
      }
    }).catchError((_) {}); // no text -> the riddle is still heard
    MagicData.load().then((_) => _newMystery());
  }

  /// "Chair" -> "C _ _ _ _" ; "Toy Rabbit" -> "T _ _   _ _ _ _ _ _"
  String _englishBlanks(String word) {
    final w = word.trim();
    if (w.isEmpty) return '?';
    final out = <String>[w[0].toUpperCase()];
    for (var i = 1; i < w.length; i++) {
      out.add(w[i] == ' ' ? ' ' : '_');
    }
    return out.join(' ');
  }

  void _newMystery() {
    final pool = Repository.instance.huntWords
        .where((w) =>
            str(w.sticker).isNotEmpty &&
            str(w.hintAudio).isNotEmpty &&
            str(w.id) != _lastId)
        .toList();
    if (pool.isEmpty) return;
    final t = pool[_rng.nextInt(pool.length)];
    setState(() {
      _target = t;
      _lastId = str(t.id);
      _cluesOpen = 0;
      _phase = _Phase.hunting;
      _seen = '';
    });
    playWord(t); // Juju says the mystery word in Arabic
  }

  /// Dig up clue [n] (only the next one can be dug), or replay an open one.
  Future<void> _clue(int n) async {
    final t = _target;
    if (t == null || n > _cluesOpen + 1) return;
    if (n > _cluesOpen) HapticFeedback.lightImpact();
    setState(() => _cluesOpen = max(_cluesOpen, n));
    switch (n) {
      case 1:
        await AudioService.instance.playAsset('hints/${str(t.hintAudio)}');
      case 2:
        await AudioIndex.instance
            .playLetter(Repository.baseLetter(str(t.letter)), withSound: true);
      case 3:
        break; // English first letter appears (C _ _ _ _)
    }
  }

  Future<void> _snap() async {
    final t = _target;
    if (t == null) return;
    final photo = await snapPhoto(context);
    if (photo == null || !mounted) return;
    // ← after    if (photo == null || !mounted) return;
    final res = await waitWithMatch(
        context, MetaGames.instance.detectiveCheck(photo, str(t.englishWord)),
        message: "I'm looking at your photo…");
    if (!mounted) return;
    if (res == null) {
      ProgressService.instance.addStars(1);
      setState(() => _phase = _Phase.couldNotCheck);
      playWord(t);
    } else if (res.match) {
      ProgressService.instance.addStars(_cluesOpen <= 1 ? 3 : 2);
      setState(() => _phase = _Phase.found);
      playWord(t);
    } else {
      setState(() {
        _phase = _Phase.tryAgain;
        _seen = res.object;
      });
      AudioService.instance.playAsset('juju/juju_en_great_trying.mp3');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    return MagicScaffold(
      title: 'Juju Detective',
      child: t == null
          ? const Center(child: CircularProgressIndicator())
          : (_phase == _Phase.found || _phase == _Phase.couldNotCheck)
              ? _foundView(t)
              : _huntView(t),
    );
  }

  // ───────────────────────── Hunt view: the dune scene ─────────────────────────

  Widget _huntView(HuntWord t) {
    final tryAgain = _phase == _Phase.tryAgain;
    final calm = MediaQuery.of(context).disableAnimations; // "reduce motion"
    final hint = _hints[str(t.id)];

    return Column(children: [
      JujuSays(
        pose: tryAgain ? JujuPose.encourage : JujuPose.thinking,
        text: tryAgain
            ? (_seen.isEmpty
                ? 'Hmm, not that one!'
                : 'Ooh, a $_seen! Not quite.')
            : 'Can you find this?',
        sub: tryAgain
            ? 'Dig up another clue!'
            : 'Not sure? Tap the sand to dig.',
        onListen: () => playWord(t),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 4))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(children: [
              const Positioned.fill(
                  child: CustomPaint(painter: _DunePainter())),
              // a magnifying glass searching the dunes (cards cover it as clues open)
              if (_cluesOpen < 3)
                Positioned.fill(child: _Sweeper(enabled: !calm)),
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _wordCard(t),
                        const SizedBox(height: 24),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          _clueSlot(
                            n: 1,
                            label: 'Riddle',
                            icon: Icons.hearing_rounded,
                            calm: calm,
                            content: Text(
                              hint?.isNotEmpty == true
                                  ? hint!
                                  : "Listen to Juju's clue!",
                              textAlign: TextAlign.center,
                              style: AppTheme.english(
                                  size: 17, weight: FontWeight.w700),
                            ),
                          ),
                          _clueSlot(
                            n: 2,
                            label: 'Letter',
                            icon: Icons.record_voice_over_rounded,
                            calm: calm,
                            content:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('It starts with ',
                                  style: AppTheme.english(
                                      size: 17, weight: FontWeight.w700)),
                              arabicLine(str(t.letter),
                                  size: 40, color: AppColors.highlight),
                            ]),
                          ),
                          _clueSlot(
                            n: 3,
                            label: 'Spelling',
                            icon: Icons.abc_rounded,
                            calm: calm,
                            content: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_englishBlanks(str(t.englishWord)),
                                  style: AppTheme.english(
                                      size: 30,
                                      weight: FontWeight.w800,
                                      color: AppColors.blue)),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 16),
      GameButton(
          label: 'I found it!', icon: Icons.photo_camera_rounded, onTap: _snap),
    ]);
  }

  /// The mystery word on a parchment card, always on show.
  Widget _wordCard(HuntWord t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _Sand.parchment,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _Sand.cardBorder, width: 2),
          boxShadow: const [
            BoxShadow(color: _Sand.cardBorder, offset: Offset(0, 5))
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: arabicLine(str(t.arabicWord), size: 56))),
          const SizedBox(width: 12),
          RoundIcon(
              icon: Icons.volume_up_rounded,
              label: 'Hear the word again',
              onTap: () => playWord(t),
              color: AppColors.accent,
              shadow: AppColors.accentShadow),
        ]),
      );

  /// One clue: a sand mound until dug, then the clue card rises out of the sand.
  Widget _clueSlot({
    required int n,
    required String label,
    required IconData icon,
    required Widget content,
    required bool calm,
  }) {
    final open = n <= _cluesOpen;
    final next = n == _cluesOpen + 1;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: calm ? 0 : 650),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, anim) {
            final isCard = child.key == ValueKey('card$n');
            if (!isCard) return FadeTransition(opacity: anim, child: child);
            return SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(anim),
              child: child,
            );
          },
          child: open
              ? KeyedSubtree(
                  key: ValueKey('card$n'),
                  child: _clueCard(n, label, icon, content, calm))
              : KeyedSubtree(
                  key: ValueKey('mound$n'),
                  child: _mound(n, label, next, calm)),
        ),
      ),
    );
  }

  Widget _mound(int n, String label, bool next, bool calm) => Semantics(
        button: next,
        enabled: next,
        label: next ? 'Dig up clue $n, $label' : 'Clue $n, locked',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: next ? () => _clue(n) : null,
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _Wiggle(
                enabled: next && !calm,
                child: Opacity(
                  opacity: next ? 1 : 0.55,
                  child: Container(
                    width: 240,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: _Sand.mound,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(120)),
                      border: Border(
                          bottom: BorderSide(color: _Sand.moundEdge, width: 5)),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              next
                                  ? Icons.touch_app_rounded
                                  : Icons.lock_rounded,
                              color: _Sand.moundText,
                              size: 20),
                          const SizedBox(width: 8),
                          Text(next ? 'Clue $n · Tap to dig' : 'Clue $n',
                              style: AppTheme.english(
                                  size: 16,
                                  weight: FontWeight.w800,
                                  color: _Sand.moundText)),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _clueCard(
          int n, String label, IconData icon, Widget content, bool calm) =>
      Semantics(
        button: n < 3,
        label: 'Clue $n, $label',
        child: GestureDetector(
          onTap: n < 3 ? () => _clue(n) : null, // tap again to hear clue 1 or 2
          child: Stack(children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _Sand.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _Sand.cardBorder, width: 2),
              ),
              child: Row(children: [
                Icon(icon, color: AppColors.blue, size: 26),
                const SizedBox(width: 10),
                Expanded(child: Center(child: content)),
              ]),
            ),
            if (!calm)
              const Positioned.fill(child: IgnorePointer(child: _SandPuff())),
          ]),
        ),
      );

  // ───────────────────────── Found view (unchanged) ─────────────────────────

  Widget _foundView(HuntWord t) {
    final checked = _phase == _Phase.found;
    return Column(children: [
      JujuSays(
        pose: JujuPose.proud,
        text: checked ? 'You solved it, detective!' : 'Great hunting!',
        sub: checked ? null : "I couldn't check this time, but I believe you!",
      ),
      const SizedBox(height: 16),
      Expanded(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 4))
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            StickerImage(str(t.sticker), size: 160),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              arabicLine(str(t.arabicWord), size: 44),
              const SizedBox(width: 12),
              RoundIcon(
                  icon: Icons.volume_up_rounded,
                  label: 'Hear the word',
                  onTap: () => playWord(t),
                  color: AppColors.accent,
                  shadow: AppColors.accentShadow),
            ]),
            Text(str(t.englishWord),
                style: AppTheme.english(
                    size: 18, weight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      GameButton(
          label: 'Next mystery',
          icon: Icons.search_rounded,
          onTap: _newMystery),
    ]);
  }
}

// ───────────────────────── Scene pieces ─────────────────────────

/// Sky, a sun peeking over the back dune, two dunes and a few wind ripples.
class _DunePainter extends CustomPainter {
  const _DunePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _Sand.sky);
    canvas.drawCircle(
        Offset(w * 0.84, h * 0.36), 26, Paint()..color = _Sand.sun);

    final back = Path()
      ..moveTo(0, h * 0.40)
      ..cubicTo(w * 0.15, h * 0.32, w * 0.30, h * 0.33, w * 0.44, h * 0.38)
      ..cubicTo(w * 0.60, h * 0.44, w * 0.77, h * 0.33, w, h * 0.37)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = _Sand.duneBack);

    final front = Path()
      ..moveTo(0, h * 0.52)
      ..cubicTo(w * 0.23, h * 0.44, w * 0.49, h * 0.51, w * 0.66, h * 0.48)
      ..cubicTo(w * 0.82, h * 0.45, w * 0.92, h * 0.47, w, h * 0.49)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = _Sand.duneFront);

    final ripple = Paint()
      ..color = _Sand.ripple.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final y in [0.60, 0.72, 0.84]) {
      final p = Path()
        ..moveTo(w * 0.08, h * y)
        ..quadraticBezierTo(w * 0.22, h * (y - 0.02), w * 0.38, h * y);
      final q = Path()
        ..moveTo(w * 0.58, h * (y + 0.03))
        ..quadraticBezierTo(w * 0.74, h * (y + 0.01), w * 0.90, h * (y + 0.03));
      canvas.drawPath(p, ripple);
      canvas.drawPath(q, ripple);
    }
  }

  @override
  bool shouldRepaint(covariant _DunePainter oldDelegate) => false;
}

/// A magnifying glass sweeping slowly across the dunes.
class _Sweeper extends StatefulWidget {
  const _Sweeper({required this.enabled});
  final bool enabled;
  @override
  State<_Sweeper> createState() => _SweeperState();
}

class _SweeperState extends State<_Sweeper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Sweeper old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.enabled) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = Curves.easeInOut.transform(_c.value);
            return Align(
              alignment: Alignment(-0.75 + 1.5 * v, -0.18),
              child: Transform.rotate(angle: -0.3 + 0.6 * v, child: child),
            );
          },
          child: Icon(Icons.search_rounded,
              size: 54, color: AppColors.ink.withOpacity(0.55)),
        ),
      );
}

/// Gentle squash-and-stretch on the mound that's ready to dig.
class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Wiggle old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.enabled) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final v = Curves.easeInOut.transform(_c.value);
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(1 + 0.05 * v, 1 - 0.04 * v, 1),
            child: child,
          );
        },
        child: widget.child,
      );
}

/// A one-shot puff of sand grains when a clue pops out.
class _SandPuff extends StatelessWidget {
  const _SandPuff();
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOut,
        builder: (_, v, __) => CustomPaint(painter: _PuffPainter(v)),
      );
}

class _PuffPainter extends CustomPainter {
  _PuffPainter(this.t);
  final double t;
  static const _grains = [
    (x: 0.28, dx: -22.0, r: 5.0),
    (x: 0.42, dx: -8.0, r: 4.0),
    (x: 0.50, dx: 4.0, r: 6.0),
    (x: 0.60, dx: 14.0, r: 4.0),
    (x: 0.72, dx: 24.0, r: 5.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final paint = Paint()..color = _Sand.mound.withOpacity(1 - t);
    for (final g in _grains) {
      final c = Offset(size.width * g.x + g.dx * t, size.height - 4 - 30 * t);
      canvas.drawCircle(c, g.r * (0.6 + 0.6 * t), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PuffPainter old) => old.t != t;
}
