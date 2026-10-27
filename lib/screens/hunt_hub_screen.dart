// Screen 7 – Treasure Hunt hub
// Big "Start hunting!" door, My Arabic Passport (Home open, other places locked),
// link to My Arabic Room (Screen 13). Juju (camera pose) hosts and speaks on arrival.

import 'package:flutter/material.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';

/// Passport places. Only Home is playable in the hackathon build.
/// Images come from generate_stickers.py --places → assets/places/stamp_<id>.webp
class _Place {
  final String id;
  final String label;
  final String emoji; // fallback if the stamp image is missing
  final bool playable;
  const _Place(this.id, this.label, this.emoji, {this.playable = false});
}

const List<_Place> _places = [
  _Place('home', 'My Home', '🏠', playable: true),
  _Place('souq', 'Souq', '🧺'),
  _Place('supermarket', 'Supermarket', '🛒'),
  _Place('beach', 'Beach', '🏖️'),
  _Place('park', 'Park', '🌳'),
  _Place('school', 'School', '🏫'),
];

/// Greyscale filter for locked stamps.
const ColorFilter _grey = ColorFilter.matrix(<double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

class HuntHubScreen extends StatefulWidget {
  const HuntHubScreen({super.key});

  @override
  State<HuntHubScreen> createState() => _HuntHubScreenState();
}

class _HuntHubScreenState extends State<HuntHubScreen> {
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak(const ['hunt_hello', 'hunt_hello_en']);
    });
  }

  @override
  void dispose() {
    AudioService.instance.stop();
    super.dispose();
  }

  /// Plays Juju's lines from assets/data/juju_lines.json one after another.
  Future<void> _speak(List<String> ids) async {
    if (_speaking) {
      AudioService.instance.stop();
    }
    _speaking = true;
    for (final id in ids) {
      if (!mounted) break;
      final line = Repository.instance.jujuLine(id);
      if (line == null)
        continue; // line not added yet → stay quiet, never crash
      await AudioService.instance.playLine(line);
    }
    _speaking = false;
  }

  /// Arabic text of a Juju line (shown in her bubble), or null.
  String? _lineArabic(String id) {
    final Object? line = Repository.instance.jujuLine(id);
    if (line is Map) {
      final a = line['arabic'];
      if (a is String && a.isNotEmpty) return a;
    }
    return null;
  }

  /// wordsFound may be a count or a collection – handle both.
  int _count(Object? v) {
    if (v is int) return v;
    if (v is Iterable) return v.length;
    if (v is Map) return v.length;
    return 0;
  }

  void _startHunt() {
    AudioService.instance.stop();
    Navigator.pushNamed(context, Routes.camera);
  }

  void _openGallery() {
    AudioService.instance.stop();
    Navigator.pushNamed(context, Routes.gallery);
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
    final total = Repository.instance.huntWords.length;
    final openCount = _places.where((p) => p.playable).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final found = _count(progress.wordsFound);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // ── Top bar: back · title · stars
                Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      semantic: 'Back to home',
                      onTap: _goBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Treasure Hunt',
                        style: AppTheme.english(
                            size: 24,
                            color: AppColors.ink,
                            weight: FontWeight.w800),
                      ),
                    ),
                    _StarsChip(stars: progress.stars),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Juju with camera + speech bubble
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // multiply blend turns the pose image's white background mint
                    ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                          AppColors.bg, BlendMode.multiply),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: AudioService.instance.playing,
                        builder: (context, talking, _) => Juju(
                          pose: talking ? JujuPose.talking : JujuPose.camera,
                          size: 180,
                          motion: JujuMotion.bounce,
                          onTap: () =>
                              _speak(const ['hunt_hello', 'hunt_hello_en']),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SpeechBubble(
                        tailOnLeft: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_lineArabic('hunt_hello') != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _lineArabic('hunt_hello')!,
                                  textDirection: TextDirection.rtl,
                                  style: AppTheme.arabic(
                                      size: 26,
                                      color: AppColors.ink,
                                      weight: FontWeight.w800),
                                ),
                              ),
                            Text(
                              "Let's go hunting!",
                              style: AppTheme.english(
                                  size: 16,
                                  color: AppColors.muted,
                                  weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Main action
                BigButton(
                  label: 'Start hunting!',
                  emoji: '📷',
                  style: BigButtonStyle.good,
                  height: 112,
                  expand: true,
                  onTap: _startHunt,
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Point at anything at home',
                    style: AppTheme.english(
                        size: 15,
                        color: AppColors.muted,
                        weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 60),

                // ── Passport header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'My Arabic Passport',
                        style: AppTheme.english(
                            size: 20,
                            color: AppColors.ink,
                            weight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '$openCount of ${_places.length} open',
                      style: AppTheme.english(
                          size: 14,
                          color: AppColors.blue,
                          weight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Stamps carousel: swipe sideways. A Row inside a horizontal
                // scroll view takes its height from the stamps, so it can't overflow.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in _places)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: SizedBox(
                            width: 96,
                            child: _StampTile(
                              place: p,
                              subtitle: p.playable
                                  ? '$found of $total found'
                                  : 'Coming soon',
                              onTap: p.playable
                                  ? _startHunt
                                  : () => _speak(
                                      const ['hunt_locked', 'hunt_locked_en']),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Link to My Arabic Room (Screen 13)
                _GalleryLink(onTap: _openGallery),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ───────────────────────── small private widgets ─────────────────────────

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
                color: AppColors.line, offset: Offset(0, 3), blurRadius: 0)
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
                color: AppColors.line, offset: Offset(0, 2), blurRadius: 0)
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

class _StampTile extends StatelessWidget {
  final _Place place;
  final String subtitle;
  final VoidCallback onTap;
  const _StampTile(
      {required this.place, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final open = place.playable;
    const double size = 64;

    // Stamps are round: clipping to a circle hides the image's white corners.
    Widget stamp = ClipOval(
      child: Image.asset(
        'assets/places/stamp_${place.id}.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, error, ___) {
          debugPrint(
              'Stamp not loaded: assets/places/stamp_${place.id}.webp → $error');
          return SizedBox(
            width: size,
            height: size,
            child: Center(
                child: Text(place.emoji, style: const TextStyle(fontSize: 34))),
          );
        },
      ),
    );

    if (open) {
      // Green ring = this place is open.
      stamp = Container(
        padding: const EdgeInsets.all(3),
        decoration:
            const BoxDecoration(color: AppColors.good, shape: BoxShape.circle),
        child: stamp,
      );
    } else {
      stamp = Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(
              opacity: 0.5,
              child: ColorFiltered(colorFilter: _grey, child: stamp)),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 14, color: AppColors.muted),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      label: open ? '${place.label}, $subtitle' : '${place.label}, coming soon',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                stamp,
                const SizedBox(height: 4),
                Text(
                  place.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.english(
                      size: 14,
                      color: open ? AppColors.ink : AppColors.muted,
                      weight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.english(
                      size: 13,
                      color: open ? AppColors.good : AppColors.muted,
                      weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryLink extends StatelessWidget {
  final VoidCallback onTap;
  const _GalleryLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'My sticker collection',
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: const [
            BoxShadow(
                color: AppColors.line, offset: Offset(0, 5), blurRadius: 0)
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('🖼️', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My sticker collection',
                            style: AppTheme.english(
                                size: 18,
                                color: AppColors.ink,
                                weight: FontWeight.w800)),
                        Text('See everything you found',
                            style: AppTheme.english(
                                size: 14,
                                color: AppColors.muted,
                                weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.blue, size: 34),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
