// Screen 14 – My writing wall (`Routes.writingWall`)
//
// Every board the child wrote in Screen 6 (Write): Juju's board pose
// (camel_board_1/2/3) + the child's OWN writing placed on the board by the app
// + the word's sticker (gently animated). Tap a board → big view + Listen.
// Filter by letter. Nothing is drawn by AI here.
//
// Entries come from Screen 6 (ProgressService.addWriting: letter, target =
// display text with full marks, png = transparent PNG bytes, wordId = sticker
// id, or the letter itself for the letter writing).

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/audio_index.dart';
import '../data/arabic_forms.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/writing_board.dart';

// ======================================================================
// Screen
// ======================================================================

class WritingWallScreen extends StatefulWidget {
  const WritingWallScreen({super.key});

  @override
  State<WritingWallScreen> createState() => _WritingWallScreenState();
}

class _WritingWallScreenState extends State<WritingWallScreen> {
  final _progress = ProgressService.instance;
  final _audio = AudioService.instance;
  String? _filter; // null = all letters
  bool _spoke = false;

  bool _argRead = false;

  @override
  void initState() {
    super.initState();
    WritingItem.init().then((_) {
      if (mounted) setState(() {}); // file-name PNGs can be found now
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argRead) return;
    _argRead = true;
    // opened from the letter hub → start on that letter
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) _filter = Repository.baseLetter(arg);
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  List<WritingItem> _entries() => WritingItem.all();

  List<String> _letters(List<WritingItem> all) {
    final present = all.map((w) => w.letter).where((l) => l.isNotEmpty).toSet();
    final order = List<String>.from(Repository.hackathonLetters);
    return [
      ...order.where(present.contains),
      ...present.where((l) => !order.contains(l)),
    ];
  }

  void _intro() {
    if (_spoke || !mounted) return;
    _spoke = true;
    final empty = _entries().isEmpty;
    _audio.say(
      empty
          ? "Your writing wall is empty. Let's write with Juju!"
          : 'Look at all your writing! Tap one to hear it.',
      voice: TtsVoice.jujuEnglish,
    );
  }

  void _listen(WritingItem w) {
    _audio.stop();
    if (w.isLetterOnly) {
      AudioIndex.instance
          .playLetter(Repository.baseLetter(w.letter), withSound: true);
    } else {
      _audio.playOrSay(
        asset: 'words/${w.wordId}_word.mp3',
        text: ArabicForms.forSpeech(w.target),
        voice: TtsVoice.lessonWord,
      );
    }
  }

  void _open(WritingItem w) {
    _listen(w);
    showDialog<void>(
      context: context,
      barrierColor: AppColors.ink.withOpacity(0.55),
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size.width * 0.70;
        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius.toDouble())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              JujuBoard(
                board: w.board,
                writing: w.image,
                sticker: w.sticker,
                size: size,
              ).animate().scale(
                  begin: const Offset(0.85, 0.85),
                  duration: 350.ms,
                  curve: Curves.easeOutBack),
              const SizedBox(height: 12),
              Text(w.target,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: AppTheme.arabic(size: 40, weight: FontWeight.w700)),
              if (w.when != null)
                Text(_dateLabel(w.when!),
                    style: AppTheme.english(size: 14, color: AppColors.muted)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: BigButton(
                    label: 'Listen',
                    icon: Icons.volume_up_rounded,
                    style: BigButtonStyle.accent,
                    expand: true,
                    onTap: () => _listen(w),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    label: 'Close',
                    icon: Icons.close_rounded,
                    style: BigButtonStyle.white,
                    expand: true,
                    onTap: () {
                      _audio.stop();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  String _dateLabel(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _progress,
          builder: (context, _) {
            final all = _entries();
            final letters = _letters(all);
            if (_filter != null && !letters.contains(_filter)) _filter = null;
            final shown = _filter == null
                ? all
                : all.where((w) => w.letter == _filter).toList();

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(all.length),
                  const SizedBox(height: 12),
                  if (all.isEmpty)
                    Expanded(child: _empty())
                  else ...[
                    if (letters.length > 1) _filterRow(letters),
                    if (letters.length > 1) const SizedBox(height: 12),
                    Expanded(child: _grid(shown)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(int count) {
    return Row(children: [
      Semantics(
        button: true,
        label: 'Back',
        child: InkWell(
          onTap: () => Navigator.maybePop(context),
          customBorder: const CircleBorder(),
          child: Container(
            width: AppTheme.minTap.toDouble(),
            height: AppTheme.minTap.toDouble(),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppColors.line, offset: const Offset(0, 4))
              ],
            ),
            child:
                Icon(Icons.arrow_back_rounded, color: AppColors.ink, size: 28),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text('My writing wall',
            style: AppTheme.english(size: 24, weight: FontWeight.w800)),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Text('✏️ $count',
            style: AppTheme.english(size: 17, weight: FontWeight.w800)),
      ),
    ]);
  }

  Widget _filterRow(List<String> letters) {
    Widget chip(String label, String? value, {bool arabic = false}) {
      final on = _filter == value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            setState(() => _filter = value);
            if (value != null) {
              AudioIndex.instance.playLetter(Repository.baseLetter(value));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: BoxConstraints(
                minWidth: AppTheme.minTap.toDouble(),
                minHeight: AppTheme.minTap.toDouble()),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                    color: on ? AppColors.accentShadow : AppColors.line,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Text(label,
                textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
                style: arabic
                    ? AppTheme.arabic(size: 30, weight: FontWeight.w700)
                    : AppTheme.english(size: 18, weight: FontWeight.w800)),
          ),
        ),
      );
    }

    return SizedBox(
      height: AppTheme.minTap.toDouble() + 8,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // letters run right to left
        children: [
          chip('All', null),
          for (final l in letters) chip(l, l, arabic: true),
        ],
      ),
    );
  }

  Widget _grid(List<WritingItem> items) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 3 : 2;
      final cell = (c.maxWidth - (cols - 1) * 12) / cols;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cell / (cell + 54),
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _card(items[i], cell)
            .animate()
            .fadeIn(delay: (40 * i.clamp(0, 10)).ms, duration: 250.ms)
            .slideY(begin: 0.08, end: 0),
      );
    });
  }

  Widget _card(WritingItem w, double cell) {
    return Semantics(
      button: true,
      label: 'Writing: ${w.target}',
      child: InkWell(
        onTap: () => _open(w),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: AppColors.line, offset: const Offset(0, 5))
            ],
          ),
          child: Column(children: [
            Expanded(
              child: Center(
                child: JujuBoard(
                  board: w.board,
                  writing: w.image,
                  sticker: w.sticker,
                  size: cell - 56,
                  animateSticker: false,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(w.target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: AppTheme.arabic(size: 24, weight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _empty() {
    final letter = _progress.currentLetter;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
            child: Juju(
                pose: JujuPose.pencil, size: 190, motion: JujuMotion.bounce)),
        const SizedBox(height: 16),
        Text('Your wall is empty!',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 26, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Write a letter with Juju and it will hang here.',
            textAlign: TextAlign.center,
            style: AppTheme.english(size: 17, color: AppColors.muted)),
        const SizedBox(height: 24),
        BigButton(
          label: "Let's write!",
          emoji: '✏️',
          style: BigButtonStyle.good,
          expand: true,
          onTap: () {
            _audio.stop();
            Navigator.pushNamed(context, Routes.letterWrite, arguments: letter);
          },
        ),
      ],
    );
  }
}
