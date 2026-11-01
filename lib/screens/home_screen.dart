import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../main.dart' show Routes;
import '../services/audio.dart';
import '../services/progress.dart';
import '../theme/app_theme.dart';
import '../widgets/arabic_text.dart';
import '../widgets/big_button.dart';
import '../widgets/juju.dart';

/// Screen 1 – Home.
/// Desert-and-sky scene. Juju waves and says hello; tapping Juju replays
/// her greeting. Two colour-coded doors preview where they lead:
///   My Letter → turquoise (matches the Letter hub)
///   Juju Magic World → sunset orange (matches the desert world)
/// Stars + Parents button (hold 3 s) on top.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _greetedThisSession = false; // greet once per app launch

  final _audio = AudioService.instance;
  final _progress = ProgressService.instance;

  Json? get _hello => Repository.instance.jujuLine('home_hello');
  Json? get _choose => Repository.instance.jujuLine('home_choose');

  @override
  void initState() {
    super.initState();
    if (!_greetedThisSession) {
      _greetedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _greet(delay: true));
    }
  }

  Future<void> _greet({bool delay = false}) async {
    await _audio.stop();
    if (delay) await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _audio.playLine(_hello, wait: true);
    if (!mounted) return;
    await _audio.playLine(_choose);
  }

  Future<void> _go(String route) async {
    await _audio.stop();
    if (!mounted) return;
    await Navigator.of(context).pushNamed(route);
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hello = _hello;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFFCDEDF8),
        body: Stack(
          children: [
            // ---- desert + sky backdrop (behind status bar too) ----
            const Positioned.fill(
              child: CustomPaint(painter: _DesertSkyPainter()),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final jujuSize = (c.maxHeight * 0.32).clamp(130.0, 270.0);
                  final doorHeight = (c.maxHeight * 0.27).clamp(150.0, 200.0);

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      children: [
                        // ---- top bar: stars + parents gate ----
                        Row(
                          children: [
                            ListenableBuilder(
                              listenable: _progress,
                              builder: (_, __) =>
                                  _StarsPill(stars: _progress.stars),
                            ),
                            const Spacer(),
                            HoldButton(onComplete: () => _go(Routes.parents)),
                          ],
                        ),

                        // ---- Juju + speech bubble ----
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Semantics(
                                button: true,
                                label: 'Hear Juju again',
                                child: GestureDetector(
                                  onTap: _greet,
                                  child: SpeechBubble(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (hello?['arabic'] != null)
                                          ArabicText(hello!['arabic'] as String,
                                              size: 40),
                                        Text(
                                          (hello?['english'] as String?) ??
                                              "Hi! I'm Juju.",
                                          style: AppTheme.english(
                                              size: 16, color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Juju standing on the dune, with a soft shadow
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: jujuSize * 0.55,
                                    height: 16,
                                    margin: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0x22704A1E),
                                      borderRadius: BorderRadius.all(
                                          Radius.elliptical(
                                              jujuSize * 0.55, 16)),
                                    ),
                                  ),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _audio.playing,
                                    builder: (_, talking, __) => Juju(
                                      pose: talking
                                          ? JujuPose.talking
                                          : JujuPose.wave,
                                      size: jujuSize,
                                      motion: JujuMotion.bounce,
                                      onTap: _greet, // say hello again
                                      semanticLabel:
                                          'Juju the camel. Tap to hear Juju.',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ---- the two colour-coded doors ----
                        SizedBox(
                          height: doorHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _DoorCard(
                                  label: 'My Letter',
                                  face: _Doors.letterFace,
                                  edge: _Doors.letterEdge,
                                  onTap: () => _go(Routes.letterHub),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('📖',
                                          style: TextStyle(fontSize: 44)),
                                      Text('My Letter',
                                          style: AppTheme.english(
                                              size: 22,
                                              color: Colors.white,
                                              weight: FontWeight.w800)),
                                      const SizedBox(height: 6),
                                      // letter in a white chip so it pops
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: ListenableBuilder(
                                          listenable: _progress,
                                          builder: (_, __) => ArabicText(
                                            _progress.currentLetter,
                                            size: 32,
                                            color: AppColors.highlight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _DoorCard(
                                  label: 'Juju Magic World',
                                  face: _Doors.worldFace,
                                  edge: _Doors.worldEdge,
                                  onTap: () => _go(Routes.juju),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('✨',
                                          style: TextStyle(fontSize: 44)),
                                      Text('Juju',
                                          style: AppTheme.english(
                                              size: 22,
                                              color: Colors.white,
                                              weight: FontWeight.w800)),
                                      Text('Magic World',
                                          style: AppTheme.english(
                                              size: 22,
                                              color: Colors.white,
                                              weight: FontWeight.w800)),
                                      Text('5 camera games',
                                          style: AppTheme.english(
                                              size: 14, color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Door colours: each door previews the world it opens.
// ---------------------------------------------------------------------------
class _Doors {
  static const letterFace = Color(0xFF17968C); // turquoise (Letter hub)
  static const letterEdge = Color(0xFF0F6E67);
  static const worldFace = Color(0xFFD9692E); // sunset orange (desert world)
  static const worldEdge = Color(0xFFA84C1D);
}

/// Chunky 3D door that sinks when pressed.
class _DoorCard extends StatefulWidget {
  const _DoorCard({
    required this.label,
    required this.face,
    required this.edge,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color face;
  final Color edge;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_DoorCard> createState() => _DoorCardState();
}

class _DoorCardState extends State<_DoorCard> {
  bool _pressed = false;

  void _set(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    const depth = AppTheme.shadowDepth;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: Stack(
          children: [
            // bottom edge (the "3D" lip)
            Positioned.fill(
              top: depth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.edge,
                  borderRadius: radius,
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33704A1E),
                        blurRadius: 12,
                        offset: Offset(0, 6)),
                  ],
                ),
              ),
            ),
            // face
            AnimatedPositioned(
              duration: const Duration(milliseconds: 80),
              left: 0,
              right: 0,
              top: _pressed ? depth : 0,
              bottom: _pressed ? 0 : depth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.face,
                  borderRadius: radius,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 2),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child:
                        FittedBox(fit: BoxFit.scaleDown, child: widget.child),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desert + sky backdrop: sky gradient, sun glow, clouds, layered dunes.
// To use an illustrated image instead, replace the CustomPaint in build()
// with Image.asset('assets/images/home_desert.png', fit: BoxFit.cover).
// ---------------------------------------------------------------------------
class _DesertSkyPainter extends CustomPainter {
  const _DesertSkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final full = Offset.zero & size;

    // sky
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9ED8F2), Color(0xFFCDEDF8), Color(0xFFFFF1D6)],
          stops: [0.0, 0.35, 0.55],
        ).createShader(full),
    );

    // sun + glow, low on the horizon
    final sun = Offset(w * 0.80, h * 0.50);
    final glowR = w * 0.38;
    canvas.drawCircle(
      sun,
      glowR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xCCFFF6D8), Color(0x00FFF6D8)],
        ).createShader(Rect.fromCircle(center: sun, radius: glowR)),
    );
    canvas.drawCircle(sun, w * 0.07, Paint()..color = const Color(0xFFFFF3C7));

    // clouds
    _cloud(canvas, Offset(w * 0.10, h * 0.17), w * 0.16);
    _cloud(canvas, Offset(w * 0.88, h * 0.14), w * 0.20);
    _cloud(canvas, Offset(w * 0.16, h * 0.39), w * 0.13);
    _cloud(canvas, Offset(w * 0.92, h * 0.37), w * 0.15);

    // far dune
    final far = Path()
      ..moveTo(0, h * 0.55)
      ..quadraticBezierTo(w * 0.25, h * 0.47, w * 0.50, h * 0.53)
      ..quadraticBezierTo(w * 0.75, h * 0.58, w, h * 0.50)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFF4DAA9));

    // middle dune
    final mid = Path()
      ..moveTo(0, h * 0.61)
      ..cubicTo(w * 0.20, h * 0.56, w * 0.38, h * 0.65, w * 0.62, h * 0.60)
      ..cubicTo(w * 0.80, h * 0.57, w * 0.90, h * 0.62, w, h * 0.60)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(mid, Paint()..color = const Color(0xFFEFC98E));

    // front dune (Juju stands here; doors sit on it)
    final frontTop = h * 0.64;
    final front = Path()
      ..moveTo(0, h * 0.69)
      ..cubicTo(w * 0.30, frontTop, w * 0.60, h * 0.71, w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFC184), Color(0xFFE6AC68)],
        ).createShader(Rect.fromLTRB(0, frontTop, w, h)),
    );
  }

  void _cloud(Canvas canvas, Offset c, double r) {
    final p = Paint()..color = Colors.white.withOpacity(0.85);
    canvas.drawCircle(c.translate(-r * 0.55, 0), r * 0.42, p);
    canvas.drawCircle(c.translate(0, -r * 0.18), r * 0.58, p);
    canvas.drawCircle(c.translate(r * 0.55, 0), r * 0.40, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(c.dx - r, c.dy - r * 0.05, c.dx + r, c.dy + r * 0.38),
        Radius.circular(r * 0.3),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarsPill extends StatelessWidget {
  const _StarsPill({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars stars',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTheme.minTap),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Text('$stars',
                style: AppTheme.english(size: 24, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
