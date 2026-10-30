import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:juju_arabic_buddy/screens/found_screen.dart';
import 'package:juju_arabic_buddy/screens/letter_read_screen.dart';
import 'package:juju_arabic_buddy/screens/letter_speak_screen.dart';
import 'package:juju_arabic_buddy/screens/letter_write_screen.dart';
import 'screens/customise_screen.dart'; // 10
import 'data/repository.dart';
import 'services/progress.dart';
import 'theme/app_theme.dart';
import 'screens/alphabet_screen.dart';
// Screens – uncomment each import (and its line in _builtScreens) once built.
import 'screens/home_screen.dart'; // 1
import 'screens/letter_hub_screen.dart'; // 2
import 'screens/letter_listen_screen.dart'; // 3
// import 'screens/letter_speak_screen.dart';  // 4
// import 'screens/letter_read_screen.dart';   // 5
// import 'screens/letter_write_screen.dart';  // 6
import 'screens/hunt_hub_screen.dart'; // 7
import 'screens/camera_screen.dart'; // 8
// import 'screens/found_screen.dart';         // 9
import 'screens/story_screen.dart'; // 11
import 'screens/sentence_screen.dart'; // 12
import 'screens/gallery_screen.dart'; // 13
import 'screens/writing_wall_screen.dart'; // 14
//import 'screens/juju_screen.dart'; // 15
import 'screens/parent_screen.dart'; // 16

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ArabicBuddyApp());
}

/// Route names for every screen in BUILD_GUIDE.md.
/// Pass data with Navigator.pushNamed(context, Routes.found, arguments: wordId).
class Routes {
  static const loader = '/'; // 0
  static const home = '/home'; // 1
  static const letterHub = '/letter'; // 2
  static const alphabet = '/alphabet'; //2a
  static const letterListen = '/letter/listen'; // 3
  static const letterSpeak = '/letter/speak'; // 4
  static const letterRead = '/letter/read'; // 5
  static const letterWrite = '/letter/write'; // 6
  static const huntHub = '/hunt'; // 7
  static const camera = '/hunt/camera'; // 8
  static const found = '/hunt/found'; // 9
  static const customise = '/hunt/customise'; // 10
  static const story = '/hunt/story'; // 11
  static const sentences = '/hunt/sentences'; // 12
  static const gallery = '/room'; // 13
  static const writingWall = '/writing-wall'; // 14
  static const juju = '/juju'; // 15
  static const parents = '/parents'; // 16

  static const titles = {
    home: (1, 'Home'),
    letterHub: (2, 'My Letter'),
    letterListen: (3, 'Listen'),
    letterSpeak: (4, 'Speak'),
    letterRead: (5, 'Read'),
    letterWrite: (6, 'Write'),
    huntHub: (7, 'Treasure Hunt'),
    camera: (8, 'Camera'),
    found: (9, 'Found it!'),
    customise: (10, 'Make it yours'),
    story: (11, 'My story'),
    sentences: (12, 'Sentences'),
    gallery: (13, 'My Arabic Room'),
    writingWall: (14, 'Writing wall'),
    juju: (15, 'Juju Corner'),
    parents: (16, 'Parents'),
  };
}

/// Screens that exist so far. Anything else opens a friendly "coming soon"
/// page, so buttons can point at screens that aren't built yet.
final Map<String, WidgetBuilder> _builtScreens = {
  Routes.loader: (_) => const LoaderScreen(),
  Routes.home: (_) => const HomeScreen(),
  Routes.huntHub: (_) => const HuntHubScreen(),
  Routes.camera: (_) => const CameraScreen(),
  Routes.found: (_) => const FoundScreen(),
  Routes.customise: (_) => const CustomiseScreen(),
  Routes.story: (_) => const StoryScreen(),
  Routes.gallery: (_) => const GalleryScreen(),
  Routes.letterHub: (_) => const LetterHubScreen(),
  Routes.alphabet: (_) => const AlphabetScreen(),
  Routes.letterRead: (_) => const LetterReadScreen(),
  Routes.letterWrite: (_) => const LetterWriteScreen(),
  Routes.letterSpeak: (_) => const LetterSpeakScreen(),
  Routes.letterListen: (_) => const LetterListenScreen(),
  Routes.sentences: (_) => const SentenceScreen(),
  //Routes.juju: (_) => const JujuScreen(),
  Routes.writingWall: (_) => const WritingWallScreen(),
  Routes.parents: (_) => const ParentScreen(),
};

class ArabicBuddyApp extends StatelessWidget {
  const ArabicBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arabic Buddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: Routes.loader,
      onGenerateRoute: (settings) {
        final WidgetBuilder builder = _builtScreens[settings.name] ??
            ((_) => ComingSoonScreen(routeName: settings.name ?? ''));
        return MaterialPageRoute(settings: settings, builder: builder);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 0 – loads all data once, then replaces itself with Home (Screen 1).
// ---------------------------------------------------------------------------
class LoaderScreen extends StatefulWidget {
  const LoaderScreen({super.key});

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_error != null) setState(() => _error = null);
    try {
      // Load words + saved progress; short minimum so the splash doesn't flash.
      await Future.wait([
        Repository.instance.load(),
        ProgressService.instance.load(),
        Future.delayed(const Duration(milliseconds: 900)),
      ]);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(Routes.home);
    } catch (e) {
      debugPrint('Loader error: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _JujuImage(pose: 'wave', size: 200),
                const SizedBox(height: 16),
                Text('Arabic Buddy',
                    style: AppTheme.english(size: 34, weight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (_error == null) ...[
                  Text('Getting Juju ready…',
                      style: AppTheme.english(color: AppColors.muted)),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 5),
                  ),
                ] else ...[
                  Text("Juju couldn't open her word box.",
                      textAlign: TextAlign.center,
                      style: AppTheme.english(color: AppColors.muted)),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Text('$_error',
                        textAlign: TextAlign.center,
                        style:
                            AppTheme.english(size: 13, color: AppColors.muted)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: _start, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder for screens not built yet (keeps every button working).
// ---------------------------------------------------------------------------
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.routeName});
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final info = Routes.titles[routeName];
    final title = info == null ? 'Screen' : 'Screen ${info.$1}: ${info.$2}';
    final canGoBack = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(title: Text(info?.$2 ?? '')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _JujuImage(pose: 'thinking', size: 160),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTheme.english(size: 24, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Juju is still building this one.',
                  style: AppTheme.english(color: AppColors.muted)),
              if (canGoBack) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small local helper until widgets/juju.dart exists.
/// Falls back to a camel emoji if the pose image isn't in assets yet.
class _JujuImage extends StatelessWidget {
  const _JujuImage({required this.pose, required this.size});
  final String pose;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/mascot/camel_$pose.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child:
            Center(child: Text('🐪', style: TextStyle(fontSize: size * 0.6))),
      ),
    );
  }
}
