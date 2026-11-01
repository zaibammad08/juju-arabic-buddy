// Treasure chest pieces for the Treasure Hunt.
//
// WobblingChest – a locked chest that wiggles while Muse Spark looks
//                 (shown on the camera screen during "thinking").
// ChestReveal   – on the Found screen: the lock turns green, the lid opens
//                 with a golden glow, the child's snap rises out and morphs
//                 into the sticker, which stays floating above the open chest.
//
// The photo only ever lives in memory. It is never written to disk.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chest_painter.dart';

/// Locked chest that wiggles until it is removed from the screen.
class WobblingChest extends StatefulWidget {
  final double width;
  const WobblingChest({super.key, this.width = 160});

  @override
  State<WobblingChest> createState() => _WobblingChestState();
}

class _WobblingChestState extends State<WobblingChest>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = MediaQuery.of(context).disableAnimations;
    if (calm) {
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
          builder: (_, __) => Transform.rotate(
            angle: sin(_c.value * 2 * pi) * 0.06,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: widget.width,
              height: widget.width * 0.79,
              child: CustomPaint(painter: ChestPainter(open: 0, total: 1)),
            ),
          ),
        ),
      );
}

/// The chest opening and the find coming out.
class ChestReveal extends StatefulWidget {
  /// Completes when everything is ready. Already-finished work: Future.value().
  final Future<void> ready;

  /// Shortest time the chest stays shut, so it never just flashes open.
  final Duration minWait;

  /// The child's snap, in memory only. Null = the sticker comes out directly.
  final Uint8List? photo;

  /// The finished sticker for the found word.
  final Widget sticker;

  final VoidCallback onRevealed;
  final VoidCallback? onFailed;
  final double height;

  const ChestReveal({
    super.key,
    required this.ready,
    required this.sticker,
    required this.onRevealed,
    this.photo,
    this.onFailed,
    this.minWait = const Duration(milliseconds: 1200),
    this.height = 340,
  });

  @override
  State<ChestReveal> createState() => _ChestRevealState();
}

class _ChestRevealState extends State<ChestReveal>
    with TickerProviderStateMixin {
  static const double _item = 200; // size of the photo / sticker box

  late final AnimationController _wobble = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _lid = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _morph = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  bool _started = false;
  bool _unlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run(MediaQuery.of(context).disableAnimations);
  }

  Future<void> _run(bool calm) async {
    final hasPhoto = widget.photo != null;
    if (!hasPhoto) _morph.value = 1; // no snap → the sticker pops out directly
    if (!calm) _wobble.repeat();
    try {
      await Future.wait([widget.ready, Future.delayed(widget.minWait)]);
    } catch (_) {
      if (!mounted) return;
      _wobble.stop();
      widget.onFailed?.call();
      return;
    }
    if (!mounted) return;
    _wobble.stop();
    setState(() => _unlocked = true);

    if (calm) {
      _lid.value = 1;
      _pop.value = 1;
      _morph.value = 1;
    } else {
      await Future.delayed(const Duration(milliseconds: 250)); // lock pops
      if (!mounted) return;
      await _lid.forward();
      if (!mounted) return;
      await _pop.forward();
      if (!mounted) return;
      if (hasPhoto) {
        await Future.delayed(const Duration(milliseconds: 500)); // see the snap
        if (!mounted) return;
        await _morph.forward();
      }
    }
    if (mounted) widget.onRevealed();
  }

  @override
  void dispose() {
    _wobble.dispose();
    _lid.dispose();
    _pop.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    // the find starts just inside the chest and rises to near the top
    final maxRise = max(60.0, widget.height - _item - 12);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_wobble, _lid, _pop, _morph]),
        builder: (_, __) {
          final p = Curves.easeOutBack.transform(_pop.value);
          final m = _morph.value;
          return SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(alignment: Alignment.bottomCenter, children: [
              if (_pop.value > 0)
                Transform.translate(
                  offset: Offset(0, -(30 + (maxRise - 30) * p)),
                  child: Transform.scale(
                    scale: 0.3 + 0.7 * p,
                    child: SizedBox(
                      width: _item,
                      height: _item,
                      child: Stack(alignment: Alignment.center, children: [
                        if (photo != null && m < 1)
                          Opacity(
                            opacity: 1 - m,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 6))
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.memory(photo,
                                    fit: BoxFit.cover,
                                    width: _item - 12,
                                    height: _item - 12,
                                    gaplessPlayback: true),
                              ),
                            ),
                          ),
                        if (m > 0)
                          Opacity(
                            opacity: m,
                            child: Transform.scale(
                              scale:
                                  0.8 + 0.2 * Curves.easeOutBack.transform(m),
                              child: widget.sticker,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Transform.rotate(
                  angle: _unlocked ? 0 : sin(_wobble.value * 2 * pi) * 0.05,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 170,
                    height: 134,
                    child: CustomPaint(
                      painter: ChestPainter(
                        open: _unlocked ? 1 : 0,
                        total: 1,
                        lid: Curves.easeOutBack.transform(_lid.value),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
