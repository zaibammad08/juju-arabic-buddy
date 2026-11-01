// Screen 2 – My Letter hub (carousel, same style as Juju Magic World)
// Compact letter card on top (big red letter, name, tap to hear), then one big
// card per skill: Listen · Speak · Read · Write. The carousel opens on the NEXT
// skill. Done skills get a green ✓. When all four are done, a last card appears:
// "Find a ب at home!" → Treasure Hunt. Turquoise background = letter world.
// Optional route argument: a letter String (from Juju's Alphabet, Screen 2a).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/audio_index.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/arabic_text.dart';

class _Skill {
  final String id; // must match ProgressService.skillOrder
  final String label;
  final JujuPose pose;
  final Color colour; // same colours as the matching Magic World games
  final String route;
  const _Skill(this.id, this.label, this.pose, this.colour, this.route);
}

const _skills = <_Skill>[
  _Skill('listen', 'Listen', JujuPose.headphones, AppColors.blue,
      Routes.letterListen),
  _Skill('speak', 'Speak', JujuPose.microphone, AppColors.good,
      Routes.letterSpeak),
  _Skill('read', 'Read', JujuPose.book, AppColors.highlight, Routes.letterRead),
  _Skill('write', 'Write', JujuPose.pencil, AppColors.accentShadow,
      Routes.letterWrite),
];

/// skillState may be an enum or a string – compare by name so both work.
bool _isState(Object? s, String name) =>
    s != null && s.toString().split('.').last == name;

class LetterHubScreen extends StatefulWidget {
  const LetterHubScreen({super.key});

  @override
  State<LetterHubScreen> createState() => _LetterHubScreenState();
}

class _LetterHubScreenState extends State<LetterHubScreen> {
  final _repo = Repository.instance;
  final _progress = ProgressService.instance;
  final _audio = AudioService.instance;

  String? _letter;
  bool _introDone = false;
  PageController? _pager;
  int _page = 0;
  bool _busy = false;

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

    // open on the NEXT skill (or the first one not done)
    var start = _skills
        .indexWhere((s) => _isState(_progress.skillState(l!, s.id), 'next'));
    if (start < 0) {
      start = _skills
          .indexWhere((s) => !_isState(_progress.skillState(l!, s.id), 'done'));
    }
    if (start < 0) start = _skills.length; // all done → the "find" card
    _page = start;
    _pager = PageController(viewportFraction: 0.74, initialPage: start);

    if (!_introDone) {
      _introDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sayIntro());
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    _audio.stop();
    super.dispose();
  }

  String get _name => _repo.letterInfo(_letter!)?.name ?? _letter!;

  bool get _allDone =>
      _progress.hasBadge(_letter!) ||
      _skills
          .every((s) => _isState(_progress.skillState(_letter!, s.id), 'done'));

  Future<void> _sayIntro() async {
    if (!mounted) return;
    await _audio.say("This week's letter is $_name! Pick a game.",
        voice: TtsVoice.jujuEnglish);
  }

  /// Letter name + sound from the audio index (TTS fallback inside).
  Future<void> _playLetter() async {
    await _audio.stop();
    AudioIndex.instance.playLetter(_letter!, withSound: true);
  }

  void _onPage(int i) {
    setState(() => _page = i);
    HapticFeedback.selectionClick();
    final label =
        i < _skills.length ? _skills[i].label : 'Find a $_name at home!';
    _audio.say(label, voice: TtsVoice.jujuEnglish);
  }

  /// Side card → slide it to the middle; middle card → open it.
  void _tapCard(int i, VoidCallback open) {
    if (i != _page) {
      _pager?.animateToPage(i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
      return;
    }
    open();
  }

  Future<void> _go(String route, {Object? arguments}) async {
    if (_busy) return;
    _busy = true;
    await _audio.stop();
    if (mounted)
      await Navigator.pushNamed(context, route, arguments: arguments);
    _busy = false;
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
            final count = _skills.length + (_allDone ? 1 : 0);
            if (_page >= count) _page = count - 1;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _topBar(),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _letterCard(letter, badge),
                ),
                const SizedBox(height: 10),

                // ── skill carousel
                Expanded(
                  child: PageView.builder(
                    controller: _pager,
                    itemCount: count,
                    onPageChanged: _onPage,
                    itemBuilder: (_, i) {
                      final active = i == _page;
                      final Widget card;
                      if (i < _skills.length) {
                        final s = _skills[i];
                        final state = _progress.skillState(letter, s.id);
                        card = _SkillCard(
                          skill: s,
                          active: active,
                          done: _isState(state, 'done'),
                          next: _isState(state, 'next'),
                          onTap: () => _tapCard(
                              i, () => _go(s.route, arguments: letter)),
                        );
                      } else {
                        card = _FindCard(
                          letter: letter,
                          active: active,
                          onTap: () => _tapCard(i, () => _go(Routes.huntHub)),
                        );
                      }
                      return AnimatedScale(
                        scale: active ? 1.0 : 0.88,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: active ? 1.0 : 0.7,
                          duration: const Duration(milliseconds: 220),
                          child: card,
                        ),
                      );
                    },
                  ),
                ),

                // ── dots
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 26 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? (i < _skills.length
                                    ? _skills[i].colour
                                    : AppColors.good)
                                : AppColors.line,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── small links
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(children: [
                    Expanded(
                      child: _LinkChip(
                        icon: Icons.grid_view_rounded,
                        label: 'All letters',
                        onTap: () => _go(Routes.alphabet),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LinkChip(
                        emoji: '🧱',
                        label: 'Writing wall',
                        onTap: () => _go(Routes.writingWall, arguments: letter),
                      ),
                    ),
                  ]),
                ),
              ],
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
        Semantics(
          button: true,
          label: 'Go back',
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _back,
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
          child: Text('My Letter',
              textAlign: TextAlign.center,
              style: AppTheme.english(size: 24, weight: FontWeight.w800)),
        ),
        Semantics(
          label: '${_progress.stars} stars',
          excludeSemantics: true,
          child: Container(
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
        ),
      ],
    );
  }

  // ── Compact letter card: big red letter · name · sound ────────
  Widget _letterCard(String letter, bool badge) {
    return Semantics(
      button: true,
      label: 'This week\'s letter, $_name. Tap to hear it.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _playLetter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Juju(
                pose: badge ? JujuPose.gradCap : JujuPose.book,
                size: 96,
                motion: badge ? JujuMotion.bounce : JujuMotion.none,
                onTap: _sayIntro,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(badge ? 'Badge earned! 🎓' : "This week's letter",
                        style: AppTheme.english(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.muted)),
                    Text(_name,
                        style: AppTheme.english(
                            size: 24, weight: FontWeight.w800)),
                  ],
                ),
              ),
              ArabicText(letter, size: 72, color: AppColors.highlight),
              const SizedBox(width: 8),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 3),
                ),
                child: const Icon(Icons.volume_up_rounded,
                    color: AppColors.ink, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── private widgets ─────────────────────────

/// Shared card shell: white card, coloured border, big picture area,
/// title row and a big Play button.
class _CardShell extends StatelessWidget {
  final Color colour;
  final bool active;
  final Widget picture;
  final Widget title;
  final IconData playIcon;
  final String semantic;
  final VoidCallback onTap;
  final List<Widget> badges;
  const _CardShell({
    required this.colour,
    required this.active,
    required this.picture,
    required this.title,
    required this.semantic,
    required this.onTap,
    this.playIcon = Icons.play_arrow_rounded,
    this.badges = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
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
                      color: colour.withOpacity(active ? 0.7 : 0.3), width: 4),
                  boxShadow: const [
                    BoxShadow(
                        color: AppColors.line,
                        offset: Offset(0, 6),
                        blurRadius: 0),
                  ],
                ),
                child: Column(children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colour.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(child: picture),
                    ),
                  ),
                  const SizedBox(height: 12),
                  title,
                  const SizedBox(height: 12),
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                            color: Color.lerp(colour, Colors.black, 0.3)!,
                            offset: const Offset(0, 5),
                            blurRadius: 0),
                      ],
                    ),
                    child: Center(
                        child: Icon(playIcon, color: Colors.white, size: 44)),
                  ),
                ]),
              ),
              ...badges,
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final _Skill skill;
  final bool active, done, next;
  final VoidCallback onTap;
  const _SkillCard({
    required this.skill,
    required this.active,
    required this.done,
    required this.next,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final jujuSize = (c.maxHeight * 0.42).clamp(110.0, 230.0);
      return _CardShell(
        colour: skill.colour,
        active: active,
        semantic:
            '${skill.label}${done ? ', done' : next ? ', next' : ''}. Tap to play.',
        onTap: onTap,
        playIcon: done ? Icons.replay_rounded : Icons.play_arrow_rounded,
        picture: Juju(
            pose: skill.pose,
            size: jujuSize,
            motion: active ? JujuMotion.bounce : JujuMotion.none),
        title: Text(skill.label,
            style: AppTheme.english(size: 26, weight: FontWeight.w800)),
        badges: [
          if (next)
            Positioned(
              top: -12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('NEXT',
                      style: AppTheme.english(
                          size: 15,
                          weight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
          if (done)
            Positioned(
              top: -10,
              right: -4,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.good,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 28),
              ),
            ),
        ],
      );
    });
  }
}

/// Appears after all 4 skills: the letter goes hunting in the real world.
class _FindCard extends StatelessWidget {
  final String letter;
  final bool active;
  final VoidCallback onTap;
  const _FindCard(
      {required this.letter, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final jujuSize = (c.maxHeight * 0.42).clamp(110.0, 230.0);
      return _CardShell(
        colour: AppColors.good,
        active: active,
        semantic: 'Find a $letter at home. Opens the Treasure Hunt.',
        onTap: onTap,
        playIcon: Icons.photo_camera_rounded,
        picture: Juju(
            pose: JujuPose.camera,
            size: jujuSize,
            motion: active ? JujuMotion.bounce : JujuMotion.none),
        title: Directionality(
          textDirection: TextDirection.ltr,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Find a ',
                  style: AppTheme.english(size: 24, weight: FontWeight.w800)),
              ArabicText(letter, size: 32, color: AppColors.highlight),
              Text(' at home!',
                  style: AppTheme.english(size: 24, weight: FontWeight.w800)),
            ]),
          ),
        ),
      );
    });
  }
}

class _LinkChip extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;
  final VoidCallback onTap;
  const _LinkChip(
      {this.icon, this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  Icon(icon, color: AppColors.blue, size: 24)
                else
                  Text(emoji ?? '', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(label,
                    style: AppTheme.english(
                        size: 16,
                        weight: FontWeight.w800,
                        color: AppColors.blue)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
