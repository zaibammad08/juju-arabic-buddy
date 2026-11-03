// Shared pieces for the Juju Magic World games.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
export 'quick_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../data/audio_index.dart';
import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/juju.dart';

// ---------------------------------------------------------------- data

class MagicData {
  static Map<String, dynamic>? _data;

  static Future<Map<String, dynamic>> load() async {
    if (_data != null) return _data!;
    try {
      final s = await rootBundle.loadString('assets/data/magic_world.json');
      _data = jsonDecode(s) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('magic_world.json: $e');
      _data = {};
    }
    return _data!;
  }

  static String audio(String id) {
    final a = _data?['audio'];
    return a is Map ? (a[id] ?? '').toString() : '';
  }
}

/// Null-safe string from a model field (works whether the field is nullable or not).
String str(Object? v) => v?.toString() ?? '';

String stickerPath(String s) =>
    s.isEmpty ? '' : (s.startsWith('assets/') ? s : 'assets/images/$s.webp');

String stickerId(String s) {
  final name = s.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

HuntWord? huntWordByEnglish(String english) {
  final e = english.trim().toLowerCase();
  if (e.isEmpty) return null;
  for (final w in Repository.instance.huntWords) {
    final n = str(w.englishWord).toLowerCase();
    if (n == e || e.contains(n) || n.contains(e)) return w;
  }
  return null;
}

Future<void> playJuju(String id) async {
  final path = MagicData.audio(id);
  if (path.isNotEmpty) await AudioService.instance.playAsset(path);
}

Future<void> playWord(HuntWord w) => AudioIndex.instance
    .playWord(str(w.arabicWord), sticker: stickerId(str(w.sticker)));

Future<void> playColour(String colourId, {required bool feminine}) =>
    AudioService.instance
        .playAsset('colours/colour_${colourId}_${feminine ? 'f' : 'm'}.mp3');

/// Takes a photo, returns the bytes and deletes the file straight away
/// (golden rule 7: photos are never saved).

// ---------------------------------------------------------------- layout

class MagicScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Color background;
  const MagicScaffold(
      {super.key,
      required this.title,
      required this.child,
      this.background = AppColors.bg});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  RoundIcon(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: AppTheme.english(
                            size: 22, weight: FontWeight.w800)),
                  ),
                  const StarChip(),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class StarChip extends StatelessWidget {
  const StarChip({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(color: AppColors.line, offset: Offset(0, 2))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, color: AppColors.accent, size: 24),
          const SizedBox(width: 4),
          Text('${ProgressService.instance.stars}',
              style: AppTheme.english(size: 18, weight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class RoundIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color iconColor;
  final Color shadow;
  final double size;
  const RoundIcon({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = AppColors.surface,
    this.iconColor = AppColors.ink,
    this.shadow = AppColors.line,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 3))],
          ),
          child: Icon(icon, color: iconColor, size: size * 0.48),
        ),
      ),
    );
  }
}

class GameButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final Color shadow;
  final Color textColor;
  final double height;
  const GameButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = AppColors.good,
    this.shadow = AppColors.goodShadow,
    this.textColor = Colors.white,
    this.height = 72,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[
                Icon(icon, color: textColor, size: 30),
                const SizedBox(width: 10)
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: AppTheme.english(
                          size: 22, weight: FontWeight.w800, color: textColor)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Juju with a speech bubble (short English line; the clip says it aloud).
class JujuSays extends StatelessWidget {
  final JujuPose pose;
  final String text;
  final String? sub;
  final double size;
  final VoidCallback? onListen;
  const JujuSays(
      {super.key,
      required this.pose,
      required this.text,
      this.sub,
      this.size = 90,
      this.onListen});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Juju(pose: pose, size: size, motion: JujuMotion.bounce),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 3))
            ],
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text,
                        style: AppTheme.english(
                            size: 18, weight: FontWeight.w800)),
                    if (sub != null)
                      Text(sub!,
                          style: AppTheme.english(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.muted)),
                  ]),
            ),
            if (onListen != null)
              RoundIcon(
                  icon: Icons.volume_up_rounded,
                  label: 'Hear Juju',
                  onTap: onListen,
                  color: AppColors.accent,
                  shadow: AppColors.accentShadow,
                  size: 48),
          ]),
        ),
      ),
    ]);
  }
}

class StickerImage extends StatelessWidget {
  final String sticker;
  final double size;
  final bool silhouette;
  const StickerImage(this.sticker,
      {super.key, this.size = 96, this.silhouette = false});

  @override
  Widget build(BuildContext context) {
    final path = stickerPath(sticker);
    Widget img = path.isEmpty
        ? Icon(Icons.image_outlined, size: size * 0.6, color: AppColors.muted)
        : Image.asset(path,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.image_outlined,
                size: size * 0.6, color: AppColors.muted));
    if (silhouette) {
      img = ColorFiltered(
          colorFilter: const ColorFilter.mode(AppColors.ink, BlendMode.srcIn),
          child: img);
    }
    return SizedBox(width: size, height: size, child: Center(child: img));
  }
}

Widget arabicLine(String text,
        {double size = 32, Color color = AppColors.ink}) =>
    Directionality(
      textDirection: TextDirection.rtl,
      child: Text(text,
          style: AppTheme.arabic(
              size: size, color: color, weight: FontWeight.w800)),
    );

// ---------------------------------------------------------------- finger drawing

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke(this.color, this.width) : points = [];
}

class DrawPadController extends ChangeNotifier {
  final GlobalKey boundaryKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  Color color = AppColors.ink;
  double width = 14;

  bool get isEmpty => _strokes.isEmpty;

  /// The colour with the most ink on the pad (by number of points).
  Color? get mainColour {
    final count = <Color, int>{};
    for (final st in _strokes) {
      count[st.color] = (count[st.color] ?? 0) + st.points.length;
    }
    if (count.isEmpty) return null;
    return count.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void undo() {
    if (_strokes.isNotEmpty) _strokes.removeLast();
    notifyListeners();
  }

  void _start(Offset p) {
    _strokes.add(_Stroke(color, width)..points.add(p));
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.points.add(p);
    notifyListeners();
  }

  Future<Uint8List?> toPng() async {
    try {
      final ro = boundaryKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final image = await ro.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('DrawPad: $e');
      return null;
    }
  }
}

class DrawPad extends StatelessWidget {
  final DrawPadController controller;
  const DrawPad({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: RepaintBoundary(
        key: controller.boundaryKey,
        child: GestureDetector(
          onPanStart: (d) => controller._start(d.localPosition),
          onPanUpdate: (d) => controller._extend(d.localPosition),
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, __) => CustomPaint(
              painter: _PadPainter(controller._strokes),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _PadPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(
            s.points.first, s.width / 2, p..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final pt in s.points.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
