// Unlock the Treasure – the ending of Treasure Hunt (bonus reading).
// Juju shows a chest with 3 locks. Each round: hear/see an Arabic word, tap the
// matching picture from the things the child found today. 3 right = chest opens.
// Arguments: List<String> of hunt word ids found this session (optional; topped up
// with words for the current letter). Uses stickers, never the child's photos.
// Each lock wobbles the chest; on the 3rd the lid flies open with a golden glow,
// confetti rains and the found stickers pop out one by one while Juju says each word.
// The chest itself is drawn by the shared ChestPainter (widgets/chest_painter.dart).
import 'dart:math';

import 'package:flutter/material.dart';

import '../../main.dart' show Routes;
import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chest_painter.dart';
import '../../widgets/juju.dart';
import 'magic_common.dart';

class TreasureUnlockScreen extends StatefulWidget {
  const TreasureUnlockScreen({super.key});
  @override
  State<TreasureUnlockScreen> createState() => _TreasureUnlockScreenState();
}

class _TreasureUnlockScreenState extends State<TreasureUnlockScreen>
    with TickerProviderStateMixin {
  static const _locks = 3;
  late final AnimationController _wobble = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _lid = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 10));
  bool _confetti = false;
  int _shown = 0; // stickers already out of the chest
  final _rng = Random();
  List<HuntWord> _found = [];
  final List<String> _done = [];
  HuntWord? _target;
  List<HuntWord> _options = [];
  String? _miss;
  bool _started = false;

  int get _open => _done.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo = Repository.instance;
    final args = ModalRoute.of(context)?.settings.arguments;
    final ids =
        args is List ? args.map((e) => e.toString()).toList() : <String>[];
    final found = <HuntWord>[];
    for (final id in ids) {
      final w = repo.huntWord(id);
      if (w != null && str(w.sticker).isNotEmpty && !found.contains(w))
        found.add(w);
    }
    final extra = [
      ...repo.huntWordsForLetter(ProgressService.instance.currentLetter),
      ...repo.huntWords,
    ].where((w) => str(w.sticker).isNotEmpty && !found.contains(w)).toList()
      ..shuffle(_rng);
    while (found.length < 6 && extra.isNotEmpty) {
      found.add(extra.removeAt(0));
    }
    _found = found;
    MagicData.load().then((_) => _nextRound());
  }

  @override
  void dispose() {
    _wobble.dispose();
    _lid.dispose();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _celebrate() async {
    final calm = MediaQuery.of(context).disableAnimations;
    _wobble.duration = const Duration(milliseconds: 900);
    await _wobble.forward(from: 0); // big excited shake
    if (!mounted) return;
    _lid.forward(from: 0);
    if (!calm) _spin.repeat();
    setState(() => _confetti = true);
    await Future.delayed(const Duration(milliseconds: 700));
    for (var i = 0; i < _done.length; i++) {
      if (!mounted) return;
      setState(() => _shown = i + 1);
      final w = Repository.instance.huntWord(_done[i]);
      if (w != null) await playWord(w);
      await Future.delayed(const Duration(milliseconds: 450));
    }
    if (mounted)
      AudioService.instance.playAsset('juju/juju_en_lesson_done.mp3');
  }

  void _nextRound() {
    final left = _found.where((w) => !_done.contains(str(w.id))).toList();
    if (left.isEmpty || _found.length < 2) return;
    final target = left[_rng.nextInt(left.length)];
    final others = _found.where((w) => w != target).toList()..shuffle(_rng);
    setState(() {
      _target = target;
      _options = ([target, ...others.take(3)])..shuffle(_rng);
      _miss = null;
    });
    playWord(target);
  }

  void _tap(HuntWord w) {
    final t = _target;
    if (t == null || _open >= _locks) return;
    if (w == t) {
      playWord(w);
      ProgressService.instance.addStars(1);
      setState(() => _done.add(str(t.id)));
      if (_open < _locks) {
        _wobble.forward(from: 0); // a lock pops, the chest jiggles
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) _nextRound();
        });
      } else {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _celebrate();
        });
      }
    } else {
      setState(() => _miss = str(w.id));
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _miss = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    final opened = _open >= _locks;
    return MagicScaffold(
      title: 'Unlock the Treasure',
      child: Stack(children: [
        Column(children: [
          SizedBox(
            height: opened ? 190 : 130,
            child: Stack(alignment: Alignment.center, children: [
              if (opened)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_spin, _lid]),
                    builder: (_, __) => CustomPaint(
                        painter: _RaysPainter(_spin.value, _lid.value)),
                  ),
                ),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Juju(
                        pose: opened ? JujuPose.proud : JujuPose.pointRight,
                        size: opened ? 110 : 96,
                        motion: JujuMotion.bounce),
                    const SizedBox(width: 6),
                    AnimatedBuilder(
                      animation: Listenable.merge([_wobble, _lid]),
                      builder: (_, __) {
                        final w = _wobble.value;
                        return Transform.rotate(
                          angle: sin(w * pi * 8) * 0.09 * (1 - w),
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: opened ? 170 : 150,
                            height: opened ? 134 : 118,
                            child: CustomPaint(
                                painter: ChestPainter(
                                    open: _open,
                                    total: _locks,
                                    lid: Curves.easeOutBack
                                        .transform(_lid.value))),
                          ),
                        );
                      },
                    ),
                  ]),
            ]),
          ),
          Text(
              opened
                  ? 'The chest is open! Look what you found!'
                  : '$_open of $_locks locks open',
              style: AppTheme.english(
                  size: 15, weight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 12),
          if (opened)
            Expanded(child: _treasure())
          else if (t != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 3))
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tap the picture of',
                            style: AppTheme.english(
                                size: 15,
                                weight: FontWeight.w700,
                                color: AppColors.muted)),
                        arabicLine(str(t.arabicWord), size: 42),
                      ]),
                ),
                RoundIcon(
                    icon: Icons.volume_up_rounded,
                    label: 'Hear the word',
                    onTap: () => playWord(t),
                    color: AppColors.accent,
                    shadow: AppColors.accentShadow),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final w in _options) _option(w)],
              ),
            ),
            Text('These are things you found today!',
                style: AppTheme.english(
                    size: 14, weight: FontWeight.w700, color: AppColors.muted)),
          ],
        ]),
        if (_confetti)
          const Positioned.fill(child: IgnorePointer(child: _Confetti())),
      ]),
    );
  }

  Widget _option(HuntWord w) {
    final miss = _miss == str(w.id);
    final right = _done.isNotEmpty && _done.last == str(w.id) && _target == w;
    return Semantics(
      button: true,
      label: str(w.englishWord),
      child: GestureDetector(
        onTap: () => _tap(w),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 120),
          offset: miss ? const Offset(0.03, 0) : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: miss ? 0.5 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: right
                    ? AppColors.good.withOpacity(0.18)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: right ? AppColors.good : AppColors.surface,
                    width: 4),
                boxShadow: const [
                  BoxShadow(color: AppColors.line, offset: Offset(0, 4))
                ],
              ),
              child: Center(child: StickerImage(str(w.sticker), size: 110)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _treasure() {
    return Column(children: [
      Expanded(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final id in _done.take(_shown))
              if (Repository.instance.huntWord(id) case final w?)
                TweenAnimationBuilder<double>(
                  key: ValueKey('out-$id'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutBack,
                  // pops up out of the chest, spins once and lands in the row
                  builder: (_, v, c) => Transform.translate(
                    offset: Offset(0, (1 - v) * -140 - sin(v * pi) * 40),
                    child: Transform.rotate(
                      angle: (1 - v) * 2 * pi,
                      child: Transform.scale(scale: 0.2 + 0.8 * v, child: c),
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => playWord(w),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.accent, width: 3),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.accentShadow,
                              offset: Offset(0, 4))
                        ],
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        StickerImage(str(w.sticker), size: 96),
                        arabicLine(str(w.arabicWord), size: 26),
                      ]),
                    ),
                  ),
                ),
          ],
        ),
      ),
      GameButton(
        label: 'Back to Magic World',
        icon: Icons.auto_fix_high_rounded,
        onTap: () => Navigator.popUntil(
            context, (r) => r.settings.name == Routes.juju || r.isFirst),
      ),
    ]);
  }
}

/// Slowly turning sunburst behind the open chest.
class _RaysPainter extends CustomPainter {
  final double turn, fade;
  _RaysPainter(this.turn, this.fade);

  @override
  void paint(Canvas canvas, Size s) {
    if (fade <= 0) return;
    final c = Offset(s.width / 2, s.height * 0.55);
    final r = s.width * 0.7;
    final p = Paint()
      ..color =
          const Color(0xFFFFD54A).withOpacity(0.28 * fade.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn * 2 * pi);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(cos(a - 0.12) * r, sin(a - 0.12) * r)
            ..lineTo(cos(a + 0.12) * r, sin(a + 0.12) * r)
            ..close(),
          p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) =>
      old.turn != turn || old.fade != fade;
}

/// One burst of confetti that falls once (about 3 s). Skipped with reduced motion.
class _Confetti extends StatefulWidget {
  const _Confetti();
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));
  final _bits = List.generate(70, (i) {
    final r = Random(i * 7 + 3);
    return (
      x: r.nextDouble(),
      delay: r.nextDouble() * 0.35,
      speed: 0.8 + r.nextDouble() * 0.6,
      drift: (r.nextDouble() - 0.5) * 60,
      spin: (r.nextDouble() - 0.5) * 14,
      w: 7 + r.nextDouble() * 6,
      color: const [
        Color(0xFFFF6B8A),
        Color(0xFFFFD54A),
        Color(0xFF1BA37B),
        Color(0xFF3E7DE0),
        Color(0xFFB79CFF),
        Color(0xFFFF9F43),
      ][i % 6],
    );
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations &&
        !_c.isAnimating &&
        _c.value == 0) _c.forward();
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
          builder: (_, __) =>
              CustomPaint(painter: _ConfettiPainter(_c.value, _bits)),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<
      ({
        double x,
        double delay,
        double speed,
        double drift,
        double spin,
        double w,
        Color color
      })> bits;
  _ConfettiPainter(this.t, this.bits);

  @override
  void paint(Canvas canvas, Size s) {
    if (t <= 0 || t >= 1) return;
    for (final b in bits) {
      final p = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * p * (s.height + 40) * b.speed;
      final x = s.width * b.x + sin(p * pi * 3) * b.drift;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * b.spin);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: b.w, height: b.w * 0.55),
              const Radius.circular(2)),
          Paint()..color = b.color.withOpacity(1 - p * 0.6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
