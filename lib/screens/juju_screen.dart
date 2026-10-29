import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';

// Screen 15: Juju World (hackathon cut)
// Tab 0: Colours backpack | Tab 1: Numbers 1-10 | Tab 2: Juju Forgets!
// Rest shows "coming soon". Nothing stored. Photos never used here.

/// Spark prompt for MetaText.sillyMistake() — wire it when hasMeta.
/// Input: correct word JSON. Output JSON only: {"wrong_id":"chair","tease_en":"Hehe..."}
/// Rules: same room/category, child-friendly, never people, English only,
/// max 15 words, never say the correct name.
const String kSillyMistakePrompt = '''
You are Juju, a silly baby camel playing with a 5-year-old.
Correct object JSON: {CORRECT_JSON}. Allowed ids: {ALLOWED_IDS}.
Pick ONE funny confusion from the same room/category.
Return JSON only: {"wrong_id":"<id>","tease_en":"<short sleepy joke, max 15 words>"}.
''';

String _stickerPath(String sticker) {
  if (sticker.isEmpty) return '';
  if (sticker.startsWith('assets/')) return sticker;
  if (sticker.contains('/')) return 'assets/$sticker';
  return 'assets/images/$sticker';
}

Color _colourDot(String id) {
  switch (id.toLowerCase()) {
    case 'red':
      return const Color(0xFFE5536B);
    case 'blue':
      return const Color(0xFF2F6FDE);
    case 'green':
      return const Color(0xFF1FA67A);
    case 'yellow':
      return const Color(0xFFF5B83D);
    case 'pink':
      return const Color(0xFFF48FB1);
    case 'orange':
      return const Color(0xFFF08A24);
    case 'purple':
      return const Color(0xFF9B7EDE);
    case 'brown':
      return const Color(0xFF8D6E63);
    case 'black':
      return const Color(0xFF0B2A3D);
    case 'white':
      return Colors.white;
    case 'grey':
    case 'gray':
      return const Color(0xFFB0BEC5);
    default:
      return AppColors.line;
  }
}

class JujuScreen extends StatefulWidget {
  const JujuScreen({super.key});
  @override
  State<JujuScreen> createState() => _JujuScreenState();
}

class _JujuScreenState extends State<JujuScreen> {
  int _tab = 0;

  // colours
  String _bagColourId = 'red';
  String _bagArabicF = '';
  bool _bagInit = false;

  // numbers
  int _count = 3;

  // forgets game
  List<dynamic> _pool = [];
  int _round = 0;
  int _score = 0;
  dynamic _correct;
  dynamic _wrong;
  String _phase = 'ask'; // ask -> pick -> cheer
  String? _feedback;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bagInit) {
      _bagInit = true;
      try {
        final c = Repository.instance.colours.firstWhere(
          (e) {
            try {
              return (e as dynamic).id == 'red';
            } catch (_) {
              return false;
            }
          },
        );
        try {
          _bagArabicF = (c as dynamic).f as String;
        } catch (_) {
          _bagArabicF = '';
        }
      } catch (_) {}
      _newForgetRound(first: true);
    }
    if (_correct == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AudioService.instance
            .say('Hi! I am Juju!', voice: TtsVoice.jujuEnglish);
      });
    }
  }

  // ---------- colours ----------

  void _pickColour(dynamic c) {
    String id = '';
    String f = '';
    String en = '';
    try {
      id = (c as dynamic).id as String;
    } catch (_) {}
    try {
      f = (c as dynamic).f as String;
    } catch (_) {}
    try {
      en = (c as dynamic).en as String;
    } catch (_) {}
    setState(() {
      _bagColourId = id;
      _bagArabicF = f;
    });
    // Spark path: if child SAID the colour, call
    // MetaVision.instance.colourFromSpeech(heardText) -> id
    // then set _bagColourId. Tap path works offline.
    if (f.isNotEmpty) {
      AudioService.instance.playOrSay(
        asset: null,
        text: f,
        voice: TtsVoice.lessonWord,
      );
    } else if (en.isNotEmpty) {
      AudioService.instance.say(en, voice: TtsVoice.jujuEnglish);
    }
    ProgressService.instance.addStars(1);
  }

  // ---------- numbers ----------

  void _sayCount() {
    // Arabic number audio lives in assets/audio/numbers/ (batch2).
    // Until filenames land in juju_lines.json, count in English + star.
    // Eastern digits shown via codepoint (not hard-coded words): ١ = 0x0661 + n-1
    AudioService.instance
        .say('$_count! Count with me!', voice: TtsVoice.jujuEnglish);
    ProgressService.instance.addStars(1);
  }

  // ---------- juju forgets ----------

  void _newForgetRound({bool first = false}) {
    try {
      if (_pool.isEmpty) {
        final all = Repository.instance.huntWords;
        _pool = List<dynamic>.from(all as List);
        _pool.shuffle(Random());
      }
    } catch (_) {
      _pool = [];
    }
    if (_pool.isEmpty) return;
    final correct = _pool[_round % _pool.length];

    // Local fallback for Spark: same room/category confusion.
    // Upgrade: replace with await MetaText.instance.sillyMistake(correct.id)
    // using kSillyMistakePrompt above. Must return wrong_id from allowed list.
    dynamic wrong;
    try {
      String room = '';
      String cat = '';
      try {
        room = (correct as dynamic).room as String;
      } catch (_) {}
      try {
        cat = (correct as dynamic).category as String;
      } catch (_) {}
      final cands = _pool.where((w) {
        if (identical(w, correct)) return false;
        String r = '';
        String cc = '';
        try {
          r = (w as dynamic).room as String;
        } catch (_) {}
        try {
          cc = (w as dynamic).category as String;
        } catch (_) {}
        return (r.isNotEmpty && r == room) || (cc.isNotEmpty && cc == cat);
      }).toList();
      cands.shuffle(Random());
      wrong = cands.isNotEmpty ? cands.first : null;
      if (wrong == null) {
        final others = _pool.where((w) => !identical(w, correct)).toList();
        others.shuffle(Random());
        wrong = others.first;
      }
    } catch (_) {
      wrong = null;
    }

    setState(() {
      _correct = correct;
      _wrong = wrong;
      _phase = 'ask';
      _feedback = null;
      _busy = false;
    });

    if (!first) return;
    // first intro is handled by header speech
  }

  String _ar(dynamic w) {
    try {
      return (w as dynamic).arabicWord as String;
    } catch (_) {
      try {
        return (w as dynamic).arabic as String;
      } catch (_) {
        return '';
      }
    }
  }

  String _en(dynamic w) {
    try {
      return (w as dynamic).englishWord as String;
    } catch (_) {
      try {
        return (w as dynamic).english as String;
      } catch (_) {
        return 'this';
      }
    }
  }

  String _audioText(dynamic w) {
    try {
      final raw = (w as dynamic).raw as Map;
      final at = raw['audio_text'] as String?;
      if (at != null && at.isNotEmpty) return at;
    } catch (_) {}
    return _ar(w);
  }

  String? _audioAsset(dynamic w) {
    try {
      final raw = (w as dynamic).raw as Map;
      final a = (raw['audio'] ?? raw['word_audio']) as String?;
      if (a != null && a.toString().isNotEmpty) return a.toString();
    } catch (_) {}
    return null;
  }

  String _sticker(dynamic w) {
    try {
      return _stickerPath((w as dynamic).sticker as String);
    } catch (_) {
      return '';
    }
  }

  Future<void> _jujuSaysWrong() async {
    if (_correct == null || _wrong == null) return;
    // Juju proudly says the WRONG name — kids love to correct her.
    await AudioService.instance.playOrSay(
      asset: _audioAsset(_wrong),
      text: _audioText(_wrong),
      voice: TtsVoice.lessonWord,
    );
  }

  void _onAskAnswer(bool saidYes) {
    if (_busy || _correct == null) return;
    if (saidYes) {
      // Child agreed with wrong Juju — be kind, blame Juju being sleepy.
      setState(() {
        _feedback = 'try';
        _phase = 'pick';
      });
      AudioService.instance
          .say('Hmm, am I sleepy? Listen again!', voice: TtsVoice.jujuEnglish);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _jujuSaysWrong();
      });
    } else {
      // Child caught her! Now prove it: tap the right one.
      setState(() {
        _feedback = 'caught';
        _phase = 'pick';
      });
      AudioService.instance
          .say('Oh no! Show me which one!', voice: TtsVoice.jujuEnglish);
      ProgressService.instance.addStars(1);
    }
  }

  void _onPick(dynamic picked) {
    if (_busy || _correct == null) return;
    final bool ok = identical(picked, _correct);
    setState(() => _busy = true);
    if (ok) {
      setState(() {
        _feedback = 'good';
        _phase = 'cheer';
        _score++;
      });
      // Model the right word right away so the name sticks.
      AudioService.instance.playOrSay(
        asset: _audioAsset(_correct),
        text: _audioText(_correct),
        voice: TtsVoice.lessonWord,
      );
      ProgressService.instance.addStars(2);
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() {
          _round++;
          _busy = false;
        });
        _newForgetRound();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _jujuSaysWrong();
        });
      });
    } else {
      setState(() {
        _feedback = 'try';
        _busy = false;
      });
      // Juju takes blame, never the child.
      AudioService.instance.say('Sorry, I missed it! Say it louder!',
          voice: TtsVoice.jujuEnglish);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _TopBar(
                tab: _tab,
                onTab: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: _tab == 0
                      ? _buildColours()
                      : _tab == 1
                          ? _buildNumbers()
                          : _buildForgets(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColours() {
    List<dynamic> colours = [];
    try {
      colours = List<dynamic>.from(Repository.instance.colours as List);
    } catch (_) {}
    if (colours.length > 8) colours = colours.sublist(0, 8);
    return Column(
      children: [
        SpeechBubble(
          tailOnLeft: false,
          child: Text(
            'What colour is my backpack?',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 17, color: AppColors.ink, weight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.center,
          children: [
            const Juju(
                pose: JujuPose.wave, size: 170, motion: JujuMotion.bounce),
            Positioned(
              bottom: 6,
              child: Container(
                width: 90,
                height: 70,
                decoration: BoxDecoration(
                  color: _colourDot(_bagColourId),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: const Center(
                  child: Text('🎒', style: TextStyle(fontSize: 36)),
                ),
              ),
            ),
          ],
        ),
        if (_bagArabicF.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child:
                ArabicText(_bagArabicF, size: 32, color: AppColors.highlight),
          ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final c in colours)
                GestureDetector(
                  onTap: () => _pickColour(c),
                  child: Builder(builder: (_) {
                    String id = '';
                    try {
                      id = (c as dynamic).id as String;
                    } catch (_) {}
                    final sel = id == _bagColourId;
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _colourDot(id),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? AppColors.highlight : AppColors.line,
                          width: sel ? 4 : 2,
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap or SAY the colour — Spark understands!',
          textAlign: TextAlign.center,
          style: AppTheme.english(
              size: 13, color: AppColors.muted, weight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildNumbers() {
    return Column(
      children: [
        SpeechBubble(
          tailOnLeft: false,
          child: Text(
            'Count with Juju! Tap a number.',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 17, color: AppColors.ink, weight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        const Juju(pose: JujuPose.wave, size: 150, motion: JujuMotion.bounce),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Column(
            children: [
              // Basket preview: N balloons/stars
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (int i = 0; i < _count; i++)
                    const Text('🎈', style: TextStyle(fontSize: 28)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (int n = 1; n <= 10; n++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _count = n);
                        _sayCount();
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: n == _count
                              ? AppColors.accent
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: n == _count
                                ? AppColors.accentShadow
                                : AppColors.line,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$n',
                            style: AppTheme.english(
                                size: 22,
                                color: AppColors.ink,
                                weight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForgets() {
    if (_correct == null || _wrong == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('Add hunt words to play!',
              style: AppTheme.english(
                  size: 15, color: AppColors.muted, weight: FontWeight.w700)),
        ),
      );
    }
    final wrongAr = _ar(_wrong);
    final opts = [_correct, _wrong]..shuffle(Random());

    return Column(
      children: [
        SpeechBubble(
          tailOnLeft: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_phase == 'ask') ...[
                // Juju says the WRONG name on purpose.
                if (wrongAr.isNotEmpty)
                  ArabicText(wrongAr, size: 34, color: AppColors.ink),
                Text(
                  'Juju says this! Is she right?',
                  textAlign: TextAlign.center,
                  style: AppTheme.english(
                      size: 15,
                      color: AppColors.muted,
                      weight: FontWeight.w700),
                ),
              ] else if (_phase == 'pick') ...[
                Text(
                  _feedback == 'caught'
                      ? 'You caught me! Tap the right one!'
                      : 'Listen again — tap the right one!',
                  textAlign: TextAlign.center,
                  style: AppTheme.english(
                      size: 16, color: AppColors.ink, weight: FontWeight.w800),
                ),
              ] else ...[
                Text(
                  'You did it! Great remembering! ⭐',
                  textAlign: TextAlign.center,
                  style: AppTheme.english(
                      size: 17, color: AppColors.ink, weight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _jujuSaysWrong,
          child: const Juju(
              pose: JujuPose.wave, size: 140, motion: JujuMotion.wiggle),
        ),
        // Correct sticker always shown — child corrects the NAME.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Column(
            children: [
              Text('Round ${_round + 1} • Stars for remembering ⭐ $_score',
                  style: AppTheme.english(
                      size: 13,
                      color: AppColors.muted,
                      weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Builder(builder: (_) {
                    final p = _sticker(_correct);
                    if (p.isEmpty) {
                      return const Center(
                          child: Text('📦', style: TextStyle(fontSize: 64)));
                    }
                    return Image.asset(p,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Text('📦', style: TextStyle(fontSize: 64))));
                  }),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _jujuSaysWrong,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.volume_up,
                      size: 30, color: AppColors.ink),
                ),
              ),
              if (_feedback == 'try' && _phase != 'cheer')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Good trying! Juju was sleepy 😴',
                      style: AppTheme.english(
                          size: 14,
                          color: AppColors.ink,
                          weight: FontWeight.w800)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_phase == 'ask')
          Row(
            children: [
              Expanded(
                child: BigButton(
                  label: 'Yes',
                  style: BigButtonStyle.good,
                  height: 72,
                  expand: true,
                  onTap: () => _onAskAnswer(true),
                  child: Text('Yes 😊',
                      style: AppTheme.english(
                          size: 20,
                          color: Colors.white,
                          weight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BigButton(
                  label: 'No',
                  style: BigButtonStyle.accent,
                  height: 72,
                  expand: true,
                  onTap: () => _onAskAnswer(false),
                  child: Text('No! 🙈',
                      style: AppTheme.english(
                          size: 20,
                          color: AppColors.ink,
                          weight: FontWeight.w800)),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              for (int i = 0; i < opts.length; i++) ...[
                Expanded(
                    child: _PickCard(
                  w: opts[i],
                  ar: _ar(opts[i]),
                  sticker: _sticker(opts[i]),
                  onTap: () => _onPick(opts[i]),
                )),
                if (i == 0) const SizedBox(width: 12),
              ],
            ],
          ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  final dynamic w;
  final String ar;
  final String sticker;
  final VoidCallback onTap;
  const _PickCard(
      {required this.w,
      required this.ar,
      required this.sticker,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: sticker.isEmpty
                    ? const Center(
                        child: Text('📦', style: TextStyle(fontSize: 48)))
                    : Image.asset(sticker,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Text('📦', style: TextStyle(fontSize: 48)))),
              ),
            ),
            const SizedBox(height: 6),
            if (ar.isNotEmpty)
              ArabicText(ar, size: 22, color: AppColors.ink)
            else
              const Icon(Icons.play_circle_fill,
                  size: 30, color: AppColors.blue),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _TopBar({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line, width: 2),
                  ),
                  child: const Icon(Icons.arrow_back,
                      size: 30, color: AppColors.ink),
                ),
              ),
              Expanded(
                child: Text('Juju World',
                    textAlign: TextAlign.center,
                    style: AppTheme.english(
                        size: 20,
                        color: AppColors.ink,
                        weight: FontWeight.w800)),
              ),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                child: Center(
                  child: ListenableBuilder(
                    listenable: ProgressService.instance,
                    builder: (_, __) => Text(
                      '⭐ ${ProgressService.instance.stars}',
                      style: AppTheme.english(
                          size: 17,
                          color: AppColors.ink,
                          weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _TabBtn(label: 'Colours', sel: tab == 0, onTap: () => onTab(0)),
            const SizedBox(width: 8),
            _TabBtn(label: 'Numbers', sel: tab == 1, onTap: () => onTab(1)),
            const SizedBox(width: 8),
            _TabBtn(label: 'Forgets!', sel: tab == 2, onTap: () => onTab(2)),
          ],
        ),
      ],
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool sel;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.sel, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: sel ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: sel ? AppColors.accentShadow : AppColors.line, width: 2),
          ),
          child: Center(
            child: Text(label,
                style: AppTheme.english(
                    size: 15, color: AppColors.ink, weight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}
