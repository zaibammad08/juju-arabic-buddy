// lib/screens/juju_screen.dart
// Screen 15 – Juju Magic World (game hub, carousel)
// Kid-first: one big game card at a time, big picture, short name, big Play
// button. Swipe to the next game and Juju says its name (for pre-readers).
// Everything fits on one screen – no scrolling.
// Parent-facing detail (skill + Juju power) stays in the data for the
// Parents screen / pitch; kids only see a small skill icon.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import 'magic/magic_common.dart';

class _Game {
  final String id; // also: assets/world/game_<id>.webp + Juju line 'game_<id>'
  final String title;
  final String subtitle; // for parents / screen readers
  final String skill;
  final String skillIcon;
  final String power; // for parents / pitch
  final String emoji; // fallback if the picture is missing
  final Color colour;
  final String route;
  final bool isNew;
  const _Game(this.id, this.title, this.subtitle, this.skill, this.skillIcon,
      this.power, this.emoji, this.colour, this.route,
      {this.isNew = false});
}

const List<_Game> _games = [
  _Game('hunt', 'Treasure Hunt', 'Snap things, then unlock the chest',
      'Speaking', '🗣️', 'SEES & NAMES', '🧰', AppColors.good, Routes.huntHub),
  _Game(
      'detective',
      'Juju Detective',
      "Follow Juju's clues, snap the answer",
      'Listening',
      '👂',
      'SOLVES CLUES',
      '🔍',
      AppColors.blue,
      Routes.detective),
  _Game('feed', 'Feed Juju', 'Find food that fits 3 clues', 'Reading', '📖',
      'THINKS WITH RULES', '🍎', AppColors.highlight, Routes.feedJuju,
      isNew: true),
  _Game(
      'playdough',
      'Playdough Magic',
      'Make a letter, add the magic dots',
      'Writing',
      '✍️',
      'TRANSFORMS',
      '✨',
      AppColors.accentShadow,
      Routes.playdough),
  _Game('story', 'Story Maker', 'Draw it, Juju tells the story', 'Drawing',
      '🖍️', 'CREATES', '🎨', AppColors.feminine, Routes.storyMaker),
];

class JujuScreen extends StatefulWidget {
  const JujuScreen({super.key});

  @override
  State<JujuScreen> createState() => _JujuScreenState();
}

class _JujuScreenState extends State<JujuScreen> {
  final _pager = PageController(viewportFraction: 0.78);
  int _page = 0;
  bool _busy = false; // blocks double-taps while a game opens

  @override
  void initState() {
    super.initState();
    MagicData.load();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _speak(const ['world_hello', 'world_hello_en']));
  }

  @override
  void dispose() {
    _pager.dispose();
    AudioService.instance.stop();
    super.dispose();
  }

  /// Plays Juju lines in order; missing lines are skipped silently.
  Future<void> _speak(List<String> ids) async {
    await AudioService.instance.stop();
    for (final id in ids) {
      if (!mounted) return;
      final line = Repository.instance.jujuLine(id);
      if (line == null) continue;
      await AudioService.instance.playLine(line, wait: true);
    }
  }

  String? _lineArabic(String id) {
    final Object? line = Repository.instance.jujuLine(id);
    if (line is Map) {
      final a = line['arabic'];
      if (a is String && a.isNotEmpty) return a;
    }
    return null;
  }

  /// Swiped to a new game → Juju names it.
  void _onPage(int i) {
    setState(() => _page = i);
    HapticFeedback.selectionClick();
    _speak(['game_${_games[i].id}']);
  }

  /// Tap a side card → slide it to the middle; tap the middle one → play.
  void _tapCard(int i) {
    if (i != _page) {
      _pager.animateToPage(i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
      return;
    }
    _open(_games[i]);
  }

  Future<void> _open(_Game g) async {
    if (_busy) return;
    _busy = true;
    await AudioService.instance.stop();
    if (mounted) await Navigator.pushNamed(context, g.route);
    _busy = false;
  }

  void _goBack() {
    AudioService.instance.stop();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3D4A0),
        body: Stack(
          children: [
            const Positioned.fill(
                child: CustomPaint(painter: _DeepDesertPainter())),
            SafeArea(
              child: LayoutBuilder(builder: (context, c) {
                final sceneH = (c.maxHeight * 0.27).clamp(150.0, 230.0);
                return Column(
                  children: [
                    // ── Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          _RoundIconButton(
                            icon: Icons.arrow_back_rounded,
                            semantic: 'Go back',
                            onTap: _goBack,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Juju Magic World',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.english(
                                    size: 24,
                                    color: AppColors.ink,
                                    weight: FontWeight.w800)),
                          ),
                          ListenableBuilder(
                            listenable: progress,
                            builder: (_, __) =>
                                _StarsChip(stars: progress.stars),
                          ),
                        ],
                      ),
                    ),

                    // ── Juju + bubble
                    SizedBox(
                      height: sceneH,
                      child: _JujuScene(
                        height: sceneH,
                        arabic: _lineArabic('world_hello'),
                        onTap: () =>
                            _speak(const ['world_hello', 'world_hello_en']),
                      ),
                    ),

                    // ── Game carousel
                    Expanded(
                      child: PageView.builder(
                        controller: _pager,
                        itemCount: _games.length,
                        onPageChanged: _onPage,
                        itemBuilder: (_, i) => AnimatedScale(
                          scale: i == _page ? 1.0 : 0.88,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: i == _page ? 1.0 : 0.7,
                            duration: const Duration(milliseconds: 220),
                            child: _GameCard(
                              game: _games[i],
                              active: i == _page,
                              onTap: () => _tapCard(i),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Dots
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _games.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 26 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? _games[i].colour
                                    : Colors.white.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── private widgets ─────────────────────────

/// Juju waving on the dune, with her bubble. Tap to hear her again.
class _JujuScene extends StatelessWidget {
  final double height;
  final String? arabic;
  final VoidCallback onTap;
  const _JujuScene(
      {required this.height, required this.arabic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final jujuSize = height * 0.92;
    return Semantics(
      button: true,
      label: 'Juju says: pick a game! Tap to hear her again.',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              Positioned(
                bottom: 2,
                right: jujuSize * 0.18,
                child: Container(
                  width: jujuSize * 0.6,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0x22704A1E),
                    borderRadius:
                        BorderRadius.all(Radius.elliptical(jujuSize * 0.6, 14)),
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: AudioService.instance.playing,
                  builder: (_, talking, __) => Juju(
                    pose: talking ? JujuPose.talking : JujuPose.wave,
                    size: jujuSize,
                    motion: JujuMotion.bounce,
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 0,
                width: 180,
                child: ValueListenableBuilder<bool>(
                  valueListenable: AudioService.instance.playing,
                  builder: (_, talking, child) => AnimatedScale(
                    scale: talking ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    child: child,
                  ),
                  child: SpeechBubble(
                    tailOnLeft: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (arabic != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(arabic!,
                                textDirection: TextDirection.rtl,
                                style: AppTheme.arabic(
                                    size: 22,
                                    color: AppColors.ink,
                                    weight: FontWeight.w800)),
                          ),
                        Text('Pick a game!',
                            style: AppTheme.english(
                                size: 16,
                                color: AppColors.ink,
                                weight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One big kid-first game card: huge picture, name, skill icon, Play.
class _GameCard extends StatelessWidget {
  final _Game game;
  final bool active;
  final VoidCallback onTap;
  const _GameCard(
      {required this.game, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Semantics(
      button: true,
      label: '${g.title}. ${g.subtitle}. Practises ${g.skill}.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: g.colour.withOpacity(active ? 0.7 : 0.3),
                      width: 4),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x55A8763A),
                        offset: Offset(0, 6),
                        blurRadius: 0),
                  ],
                ),
                child: Column(
                  children: [
                    // big picture
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: g.colour.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/world/game_${g.id}.webp',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(g.emoji,
                                    style: const TextStyle(fontSize: 110)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // name + skill icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(g.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.english(
                                  size: 24,
                                  color: AppColors.ink,
                                  weight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        Text(g.skillIcon, style: const TextStyle(fontSize: 22)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // big Play button
                    Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: g.colour,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                              color: Color.lerp(g.colour, Colors.black, 0.3)!,
                              offset: const Offset(0, 5),
                              blurRadius: 0),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 46),
                      ),
                    ),
                  ],
                ),
              ),
              if (g.isNew)
                Positioned(
                  top: -4,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('New!',
                        style: AppTheme.english(
                            size: 14,
                            color: AppColors.ink,
                            weight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parent feature, kept out of kids' reach behind the hold gate.
class _ParentsStrip extends StatelessWidget {
  final VoidCallback onOpen;
  const _ParentsStrip({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined,
              color: AppColors.muted, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Parents: snap a school page, Juju makes a lesson',
                style: AppTheme.english(
                    size: 13, color: AppColors.muted, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          HoldButton(onComplete: onOpen),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String semantic;
  final VoidCallback onTap;
  const _RoundIconButton(
      {required this.icon, required this.semantic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: Container(
        width: AppTheme.minTap,
        height: AppTheme.minTap,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Color(0x55A8763A), offset: Offset(0, 3), blurRadius: 0)
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, color: AppColors.ink, size: 30),
          ),
        ),
      ),
    );
  }
}

class _StarsChip extends StatelessWidget {
  final int stars;
  const _StarsChip({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars stars',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55A8763A), offset: Offset(0, 2), blurRadius: 0)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 24),
            const SizedBox(width: 4),
            Text('$stars',
                style: AppTheme.english(
                    size: 18, color: AppColors.ink, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// "Deep in the desert": a short warm sky; dunes fill most of the screen.
/// Home is sky-heavy and this one is sand-heavy, so kids feel they travelled.
class _DeepDesertPainter extends CustomPainter {
  const _DeepDesertPainter();

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
          colors: [Color(0xFFAEDDF0), Color(0xFFFFE9C4)],
          stops: [0.0, 0.28],
        ).createShader(full),
    );

    // sun + glow
    final sun = Offset(w * 0.18, h * 0.20);
    canvas.drawCircle(
      sun,
      w * 0.30,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xAAFFF3CF), Color(0x00FFF3CF)],
        ).createShader(Rect.fromCircle(center: sun, radius: w * 0.30)),
    );
    canvas.drawCircle(sun, w * 0.06, Paint()..color = const Color(0xFFFFF0BF));

    // dunes, back to front
    void dune(double y0, double c1, double c2, double y1, List<Color> cols) {
      final top = h * (y0 < y1 ? y0 : y1) - h * 0.04;
      final p = Path()
        ..moveTo(0, h * y0)
        ..cubicTo(w * 0.3, h * c1, w * 0.65, h * c2, w, h * y1)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: cols,
          ).createShader(Rect.fromLTRB(0, top, w, h)),
      );
    }

    dune(0.27, 0.22, 0.30, 0.25, const [Color(0xFFF6DDAE), Color(0xFFF2D19A)]);
    dune(0.36, 0.31, 0.40, 0.33, const [Color(0xFFF1CB8F), Color(0xFFEBBE7E)]);
    dune(0.47, 0.42, 0.50, 0.44, const [Color(0xFFEDBF80), Color(0xFFE2AA66)]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
