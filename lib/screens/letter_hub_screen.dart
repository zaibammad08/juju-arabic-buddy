// Screen 2 – My Letter hub
// This week's letter (big, red, tap to hear), 4 skill tiles
// (Listen · Speak · Read · Write with ✓ / NEXT / todo),
// "Find a ب at home!" → camera, parent tip.
// Optional route argument: a letter String (from Juju's Alphabet, Screen 2a).

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';
import '../widgets/skill_tile.dart';
import '../widgets/parent_tip.dart';
import '../data/audio_index.dart';

class LetterHubScreen extends StatefulWidget {
  const LetterHubScreen({super.key});

  @override
  State<LetterHubScreen> createState() => _LetterHubScreenState();
}

class _Skill {
  final String id; // must match ProgressService.skillOrder
  final String label;
  final JujuPose pose;
  final String route;
  const _Skill(this.id, this.label, this.pose, this.route);
}

const _skills = <_Skill>[
  _Skill('listen', 'Listen', JujuPose.headphones, Routes.letterListen),
  _Skill('speak', 'Speak', JujuPose.microphone, Routes.letterSpeak),
  _Skill('read', 'Read', JujuPose.book, Routes.letterRead),
  _Skill('write', 'Write', JujuPose.pencil, Routes.letterWrite),
];

const _parentTip =
    '15 minutes together is enough. Do one skill a day, in any order.';

class _LetterHubScreenState extends State<LetterHubScreen> {
  final _repo = Repository.instance;
  final _progress = ProgressService.instance;
  final _audio = AudioService.instance;

  String? _letter;
  bool _introDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_letter != null) return;

    // 1) letter passed from the Alphabet screen, 2) saved current letter, 3) ب
    final arg = ModalRoute.of(context)?.settings.arguments;
    String? l = arg is String ? Repository.baseLetter(arg) : null;
    if (l != null && _repo.isOpenLetter(l)) {
      if (_progress.currentLetter != l) {
        final newLetter = l;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _progress.setLetter(newLetter);
        });
      }
    } else {
      l = _progress.currentLetter;
    }
    if (!_repo.isOpenLetter(l)) l = Repository.hackathonLetters[1]; // ب
    _letter = l;

    if (!_introDone) {
      _introDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sayIntro());
    }
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  String get _name => _repo.letterInfo(_letter!)?.name ?? _letter!;

  Future<void> _sayIntro() async {
    if (!mounted) return;
    await _audio.say("This week's letter is $_name! Pick a game.",
        voice: TtsVoice.jujuEnglish);
  }

  /// Letter name + sound. Uses the lesson file's audio if it has one,
  /// otherwise live TTS (cached by AudioService).
  final _testPlayer = AudioPlayer();

  Future<void> _playLetter() async {
    try {
      await _testPlayer.setVolume(1.0);
      await _testPlayer.play(AssetSource('audio/letters/baa_name.mp3'));
      debugPrint('AUDIO TEST: play started');
    } catch (e) {
      debugPrint('AUDIO TEST ERROR: $e');
    }
  }

  void _openSkill(_Skill s) {
    _audio.stop();
    Navigator.pushNamed(context, s.route, arguments: _letter);
  }

  void _findAtHome() {
    _audio.stop();
    Navigator.pushNamed(context, Routes.camera, arguments: {'letter': _letter});
  }

  void _back() {
    _audio.stop();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _progress,
          builder: (context, _) {
            final letter = _letter!;
            final badge = _progress.hasBadge(letter);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  _letterCard(letter, badge),
                  const SizedBox(height: 22),
                  _skillRow(letter),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        _audio.stop();
                        Navigator.pushNamed(context, Routes.alphabet);
                      },
                      icon: const Icon(Icons.grid_view_rounded,
                          color: AppColors.blue),
                      label: Text('All letters',
                          style: AppTheme.english(
                              size: 18,
                              weight: FontWeight.w800,
                              color: AppColors.blue)),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(160, AppTheme.minTap)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _findButton(letter),
                  const SizedBox(height: 16),
                  ParentTip(
                    text: _parentTip,
                    onListen: () =>
                        _audio.say(_parentTip, voice: TtsVoice.parent),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Top bar: back · title · stars ─────────────────────────────
  Widget _topBar() {
    return Row(
      children: [
        _roundButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to home',
          onTap: _back,
        ),
        Expanded(
          child: Text('My Letter',
              textAlign: TextAlign.center,
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 3)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 24),
            const SizedBox(width: 4),
            Text('${_progress.stars}',
                style: AppTheme.english(size: 18, weight: FontWeight.w800)),
          ]),
        ),
      ],
    );
  }

  Widget _roundButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: AppTheme.minTap,
            height: AppTheme.minTap,
            child: Icon(icon, color: AppColors.ink, size: 28),
          ),
        ),
      ),
    );
  }

  // ── Letter card: Juju + big red letter + name + sound button ──
  Widget _letterCard(String letter, bool badge) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Juju(
            pose: badge ? JujuPose.gradCap : JujuPose.book,
            size: 160,
            motion: badge ? JujuMotion.bounce : JujuMotion.none,
            onTap: _sayIntro,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Text(badge ? 'Letter badge earned!' : "This week's letter",
                    textAlign: TextAlign.center,
                    style: AppTheme.english(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.muted)),
                GestureDetector(
                  onTap: _playLetter,
                  child: ArabicText(
                    letter,
                    size: 104,
                    color: AppColors.highlight,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_name,
                        style: AppTheme.english(
                            size: 24, weight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    _soundButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundButton() {
    return Semantics(
      button: true,
      label: 'Hear the letter',
      child: Material(
        color: AppColors.surface2,
        shape: const CircleBorder(
            side: BorderSide(color: AppColors.accent, width: 3)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _playLetter,
          child: const SizedBox(
            width: AppTheme.minTap,
            height: AppTheme.minTap,
            child:
                Icon(Icons.volume_up_rounded, color: AppColors.ink, size: 30),
          ),
        ),
      ),
    );
  }

  // ── 4 skill tiles in a row ────────────────────────────────────
  Widget _skillRow(String letter) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _skills.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: SkillTile(
              label: _skills[i].label,
              pose: _skills[i].pose,
              state: _progress.skillState(letter, _skills[i].id),
              onTap: () => _openSkill(_skills[i]),
            ),
          ),
        ],
      ],
    );
  }

  // ── "Find a ب at home!" → camera ──────────────────────────────
  Widget _findButton(String letter) {
    return BigButton(
      label: 'Find a $_name at home!',
      style: BigButtonStyle.good,
      height: 80,
      onTap: _findAtHome,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_rounded,
                color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Text('Find a ',
                style: AppTheme.english(
                    size: 22, weight: FontWeight.w800, color: Colors.white)),
            ArabicText(letter, size: 30, color: Colors.white),
            Text(' at home!',
                style: AppTheme.english(
                    size: 22, weight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
