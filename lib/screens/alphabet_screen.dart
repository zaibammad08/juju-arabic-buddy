// Screen 2a – Juju's Alphabet
// 28 letters in Arabic order, right-to-left grid (4 per row).
// Juju wears the blank neck board (camel_board_3); the APP writes the tapped
// letter on it. Open letters (ا ب م د س) → name, then their My Letter hub.
// Locked letters → name, then "Coming soon!".

import 'package:flutter/material.dart';
import 'package:juju_arabic_buddy/data/audio_index.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/arabic_text.dart';

/// Where the board sits inside the camel_board_3 picture.
/// Tune these two once you see the real image.
const _boardCenter =
    Alignment(0.0, 0.38); // x: -1 left … 1 right, y: -1 top … 1 bottom
const _boardTextSize = 60.0;
const _jujuSize = 200.0;

class AlphabetScreen extends StatefulWidget {
  const AlphabetScreen({super.key});

  @override
  State<AlphabetScreen> createState() => _AlphabetScreenState();
}

class _AlphabetScreenState extends State<AlphabetScreen> {
  final _repo = Repository.instance;
  final _audio = AudioService.instance;

  late final List<String> _letters = _repo.letters.keys.toList(); // ا … ي
  String? _shown;
  bool _comingSoon = false;
  int _tapId = 0; // a newer tap cancels the older one

  @override
  void initState() {
    super.initState();
    _shown = ProgressService.instance.currentLetter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _audio.say('Tap a letter!', voice: TtsVoice.jujuEnglish);
    });
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  String _name(String l) => _repo.letterInfo(l)?.name ?? '';

  Future<void> _onTap(String l) async {
    final id = ++_tapId;
    final open = _repo.isOpenLetter(l);
    setState(() {
      _shown = l;
      _comingSoon = !open;
    });

    await _audio.stop();
    // Letter name (live TTS for now; switches to the batch2 files later).
    await AudioIndex.instance.playLetter(l, withSound: !open);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || id != _tapId) return;

    if (open) {
      // Keep the stack short: Home → Hub (back from the hub goes Home).
      Navigator.pushNamedAndRemoveUntil(
        context,
        Routes.letterHub,
        (r) => r.settings.name == Routes.home || r.isFirst,
        arguments: l,
      );
    } else {
      await _audio.say('Coming soon!', voice: TtsVoice.jujuEnglish);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _topBar(),
            ),
            _jujuBoard(),
            Expanded(child: _grid()),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────
  Widget _topBar() {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                _audio.stop();
                Navigator.maybePop(context);
              },
              child: const SizedBox(
                width: AppTheme.minTap,
                height: AppTheme.minTap,
                child: Icon(Icons.arrow_back_rounded,
                    color: AppColors.ink, size: 28),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text("Juju's Alphabet",
              textAlign: TextAlign.center,
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
        ),
        const SizedBox(width: AppTheme.minTap), // balances the back button
      ],
    );
  }

  // ── Juju with the letter on her board ─────────────────────────
  Widget _jujuBoard() {
    final l = _shown;
    return Column(
      children: [
        SizedBox(
          width: _jujuSize,
          height: _jujuSize,
          child: Stack(
            children: [
              Positioned.fill(
                child: Juju(
                  pose: JujuPose.board3,
                  size: _jujuSize,
                  motion: JujuMotion.none,
                  onTap: l == null ? null : () => _onTap(l),
                ),
              ),
              if (l != null)
                Align(
                  alignment: _boardCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: ArabicText(
                      l,
                      key: ValueKey(l),
                      size: _boardTextSize,
                      color: AppColors.highlight,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              l == null
                  ? ''
                  : _comingSoon
                      ? '${_name(l)} · Coming soon!'
                      : _name(l),
              key: ValueKey('$l$_comingSoon'),
              style: AppTheme.english(
                  size: 20,
                  weight: FontWeight.w800,
                  color: _comingSoon ? AppColors.muted : AppColors.ink),
            ),
          ),
        ),
      ],
    );
  }

  // ── 28 letters, right-to-left, 4 per row ──────────────────────
  Widget _grid() {
    return Directionality(
      textDirection: TextDirection.rtl, // ا starts top-right
      child: GridView.count(
        crossAxisCount: 4,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [for (final l in _letters) _tile(l)],
      ),
    );
  }

  Widget _tile(String l) {
    final open = _repo.isOpenLetter(l);
    final selected = l == _shown;
    return Semantics(
      button: true,
      label: '${_name(l)}${open ? '' : ', coming soon'}',
      child: Material(
        color: open ? AppColors.surface : AppColors.surface2,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _onTap(l),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? AppColors.accent
                    : (open ? AppColors.surface : AppColors.line),
                width: 3,
              ),
              boxShadow: open
                  ? const [
                      BoxShadow(
                          color: AppColors.accentShadow, offset: Offset(0, 4))
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: ArabicText(
                    l,
                    size: 40,
                    color: open
                        ? AppColors.highlight
                        : AppColors.muted.withOpacity(0.55),
                  ),
                ),
                if (!open)
                  const Positioned(
                    top: 6,
                    left: 6, // RTL: left is the far corner
                    child: Icon(Icons.lock_rounded,
                        size: 16, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
