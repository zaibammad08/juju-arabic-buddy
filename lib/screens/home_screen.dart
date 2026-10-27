import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../main.dart' show Routes;
import '../services/audio.dart';
import '../services/progress.dart';
import '../theme/app_theme.dart';
import '../widgets/arabic_text.dart';
import '../widgets/big_button.dart';
import '../widgets/juju.dart';

/// Screen 1 – Home.
/// Juju waves and says hello, two big doors (My Letter / Treasure Hunt),
/// stars, and the Parents button (hold 3 s). Tap Juju → Juju Corner.
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
    }
  }

  Future<void> _greet() async {
    await Future.delayed(const Duration(milliseconds: 400));
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

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final jujuSize = (c.maxHeight * 0.30).clamp(130.0, 260.0);
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
                        builder: (_, __) => _StarsPill(stars: _progress.stars),
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
                        ValueListenableBuilder<bool>(
                          valueListenable: _audio.playing,
                          builder: (_, talking, __) => Juju(
                            pose: talking ? JujuPose.talking : JujuPose.wave,
                            size: jujuSize,
                            motion: JujuMotion.bounce,
                            onTap: () => _go(Routes.juju),
                            semanticLabel:
                                'Juju the camel. Tap to play with Juju.',
                          ),
                        ),
                        Text('Tap Juju to play!',
                            style: AppTheme.english(
                                size: 14, color: AppColors.muted)),
                      ],
                    ),
                  ),

                  // ---- the two doors ----
                  SizedBox(
                    height: doorHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: BigButton(
                            label: 'My Letter',
                            style: BigButtonStyle.accent,
                            height: doorHeight - AppTheme.shadowDepth,
                            onTap: () => _go(Routes.letterHub),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('📖',
                                      style: TextStyle(fontSize: 44)),
                                  Text('My Letter',
                                      style: AppTheme.english(
                                          size: 22, weight: FontWeight.w800)),
                                  ListenableBuilder(
                                    listenable: _progress,
                                    builder: (_, __) => ArabicText(
                                      _progress.currentLetter,
                                      size: 34,
                                      color: AppColors.highlight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: BigButton(
                            label: 'Treasure Hunt',
                            style: BigButtonStyle.good,
                            height: doorHeight - AppTheme.shadowDepth,
                            onTap: () => _go(Routes.huntHub),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('📷',
                                      style: TextStyle(fontSize: 44)),
                                  Text('Treasure Hunt',
                                      style: AppTheme.english(
                                          size: 22,
                                          color: Colors.white,
                                          weight: FontWeight.w800)),
                                  Text('Find words at home',
                                      style: AppTheme.english(
                                          size: 14, color: Colors.white)),
                                ],
                              ),
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
    );
  }
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
