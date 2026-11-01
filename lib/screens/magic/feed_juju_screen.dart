// Feed Juju – READING. Juju shows 3 Arabic clue words (e.g. red · round · fruit);
// the child reads them, finds food that fits all 3 and snaps it. Muse Spark checks
// each rule separately, so Juju can explain which clue didn't fit.
// Riddles live in assets/data/magic_world.json ("feed_riddles").
//
// Riddle view: Juju stands in the desert (same sand as Detective) with an empty
// basket. After the check she reacts in the scene first (eats the photo / leaves
// it on the sand and tilts her head), then the result view opens.
// Not-quite view stays in the desert: the snack sits on the sand, Juju's line
// depends on how many clues matched, and compact rows show each clue.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../services/audio.dart';
import '../../services/meta_games.dart';
import '../../services/progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/feed_juju_desert.dart';
import '../../widgets/juju.dart';
import '../../widgets/loading_match.dart';
import 'magic_common.dart';

class _Clue {
  final String arabic;
  final String english;
  final String audio;
  final String rule;
  const _Clue(this.arabic, this.english, this.audio, this.rule);
}

enum _Phase { riddle, result, couldNotCheck }

class FeedJujuScreen extends StatefulWidget {
  const FeedJujuScreen({super.key});
  @override
  State<FeedJujuScreen> createState() => _FeedJujuScreenState();
}

class _FeedJujuScreenState extends State<FeedJujuScreen> {
  final _rng = Random();
  List<Map<String, dynamic>> _riddles = [];
  int _index = -1;
  List<_Clue> _clues = [];
  _Phase _phase = _Phase.riddle;
  FeedCheck? _check;
  Uint8List? _photo; // kept in memory for this screen only, never saved

  FeedMood _mood = FeedMood.hungry;
  bool _busy = false; // blocks double taps while Juju is reacting

  static const _eatTime = Duration(milliseconds: 1800);
  static const _tiltTime = Duration(milliseconds: 1300);

  Map<String, dynamic> get _riddle => _riddles[_index];

  @override
  void initState() {
    super.initState();
    MagicData.load().then((d) {
      final list = d['feed_riddles'];
      if (list is List) {
        _riddles = list.whereType<Map<String, dynamic>>().toList();
      }
      _next();
    });
  }

  void _next() {
    if (_riddles.isEmpty) return;
    var i = _rng.nextInt(_riddles.length);
    if (_riddles.length > 1 && i == _index) i = (i + 1) % _riddles.length;
    final clues = <_Clue>[];
    for (final c in (_riddles[i]['clues'] as List? ?? const [])) {
      if (c is! Map) continue;
      final rule = str(c['rule']);
      switch (str(c['type'])) {
        case 'colour':
          final col = Repository.instance.colour(str(c['id']));
          if (col != null) {
            clues.add(_Clue(str(col.m), str(col.en),
                'colours/colour_${str(col.id)}_m.mp3', rule));
          }
        case 'adjective':
          final adj = Repository.instance.adjective(str(c['id']));
          if (adj != null) {
            clues.add(_Clue(str(adj.m), str(adj.en),
                'adjectives/adj_${str(adj.id)}_m.mp3', rule));
          }
        default:
          clues.add(_Clue(
              str(c['arabic']), str(c['english']), str(c['audio']), rule));
      }
    }
    setState(() {
      _index = i;
      _clues = clues;
      _phase = _Phase.riddle;
      _check = null;
      _photo = null;
      _mood = FeedMood.hungry;
      _busy = false;
    });
    playJuju('feed_hungry');
  }

  Future<void> _snap() async {
    if (_busy) return;
    _busy = true;
    try {
      final photo = await snapPhoto();
      if (photo == null || !mounted) return;
      final res = await waitWithMatch(context,
          MetaGames.instance.feedCheck(photo, [for (final c in _clues) c.rule]),
          message: "I'm checking your food…");
      if (!mounted) return;

      if (res == null) {
        setState(() {
          _photo = photo;
          _check = null;
          _phase = _Phase.couldNotCheck;
        });
        ProgressService.instance.addStars(1);
        return;
      }

      // 1) Juju reacts in the desert first.
      setState(() {
        _photo = photo;
        _check = res;
        _mood = res.allPass ? FeedMood.eating : FeedMood.notQuite;
      });
      if (res.allPass) {
        ProgressService.instance.addStars(3);
        final w = huntWordByEnglish(res.object);
        if (w != null) playWord(w);
      } else {
        AudioService.instance.playAsset('juju/juju_en_great_trying.mp3');
      }
      await Future.delayed(res.allPass ? _eatTime : _tiltTime);
      if (!mounted) return;

      // 2) Then the result view.
      setState(() {
        _phase = _Phase.result;
        _mood = FeedMood.hungry;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MagicScaffold(
      title: 'Feed Juju',
      background: AppColors.surface2,
      child: _index < 0
          ? const Center(child: CircularProgressIndicator())
          : switch (_phase) {
              _Phase.riddle => _riddleView(),
              _Phase.result =>
                _check!.allPass ? _yumView(_check!) : _notQuiteView(_check!),
              _Phase.couldNotCheck => _couldNotCheckView(),
            },
    );
  }

  // ------------------------------------------------------------- riddle

  Widget _riddleView() {
    return Column(children: [
      _speechCard(),
      const SizedBox(height: 14),
      Row(children: [
        for (var i = 0; i < _clues.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _clueCard(_clues[i])),
        ],
      ]),
      const SizedBox(height: 14),
      Expanded(
        child: FeedJujuDesert(
          mood: _mood,
          food: _mood == FeedMood.hungry ? null : _photoBite(),
          foodSpot:
              _mood == FeedMood.notQuite ? FoodSpot.sand : FoodSpot.basket,
          onJujuTap: () => playJuju('feed_hungry'),
          jujuBuilder: _jujuFor,
        ),
      ),
      const SizedBox(height: 14),
      GameButton(
          label: 'Show Juju!', icon: Icons.photo_camera_rounded, onTap: _snap),
      const SizedBox(height: 8),
      Text("Point the camera at things, not faces. Photos aren't saved.",
          textAlign: TextAlign.center,
          style: AppTheme.english(
              size: 13, weight: FontWeight.w600, color: AppColors.muted)),
    ]);
  }

  Widget _jujuFor(FeedMood mood, double size) => Juju(
        pose: switch (mood) {
          FeedMood.hungry => JujuPose.idle,
          FeedMood.eating => JujuPose.happy,
          FeedMood.notQuite => JujuPose.confused,
        },
        size: size,
      );

  /// Riddle-phase line (changes while Juju reacts).
  Widget _speechCard() {
    final (text, sub) = switch (_mood) {
      FeedMood.eating => ('Yum yum!', 'Munch, munch…'),
      FeedMood.notQuite => ('Hmm…', 'Let me look again.'),
      FeedMood.hungry => (
          'My tummy is rumbling!',
          'Find me something that is all 3:'
        ),
    };
    return _bubble(text, sub, onListen: () => playJuju('feed_hungry'));
  }

  /// Juju's line, full width now that Juju herself lives in the desert.
  Widget _bubble(String text, String sub,
      {required VoidCallback onListen, Widget? extra}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                style: AppTheme.english(size: 22, weight: FontWeight.w800)),
            // The word finishes Juju's sentence ("that's a… هَاتِف"),
            // so it sits right under it, before the hint line.
            if (extra != null) ...[const SizedBox(height: 2), extra],
            const SizedBox(height: 2),
            Text(sub,
                style: AppTheme.english(
                    size: 15, weight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        RoundIcon(
            icon: Icons.volume_up_rounded,
            label: 'Hear Juju',
            onTap: onListen,
            color: AppColors.accent,
            shadow: AppColors.accentShadow,
            size: 56),
      ]),
    );
  }

  /// The child's own photo as a round "snack" that drops into the basket.
  Widget? _photoBite() {
    if (_photo == null) return null;
    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(5),
      child: ClipOval(child: Image.memory(_photo!, fit: BoxFit.cover)),
    );
  }

  Widget _clueCard(_Clue c) {
    return GestureDetector(
      onTap: c.audio.isEmpty
          ? null
          : () => AudioService.instance.playAsset(c.audio),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: AppColors.line, offset: Offset(0, 4))
          ],
        ),
        child: Column(children: [
          FittedBox(
              fit: BoxFit.scaleDown, child: arabicLine(c.arabic, size: 28)),
          Text(c.english,
              style: AppTheme.english(
                  size: 14, weight: FontWeight.w700, color: AppColors.muted)),
          if (c.audio.isNotEmpty)
            const Icon(Icons.volume_up_rounded,
                color: AppColors.accentShadow, size: 22),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------- results

  Widget _photoBox({double height = 190}) => ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: height,
          width: double.infinity,
          color: AppColors.line,
          child:
              _photo == null ? null : Image.memory(_photo!, fit: BoxFit.cover),
        ),
      );

  Widget _ruleRow(_Clue c, bool pass) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: pass ? AppColors.surface : AppColors.accent, width: 3),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: pass ? AppColors.good : AppColors.tip,
              shape: BoxShape.circle,
              border:
                  pass ? null : Border.all(color: AppColors.accent, width: 2)),
          child: Icon(pass ? Icons.check_rounded : Icons.help_outline_rounded,
              color: pass ? Colors.white : AppColors.accentShadow, size: 20),
        ),
        const SizedBox(width: 12),
        SizedBox(
            width: 92,
            child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: arabicLine(c.arabic, size: 22))),
        Expanded(
          child: Text(pass ? 'Yes, ${c.english}!' : 'Not ${c.english} yet',
              style: AppTheme.english(size: 15, weight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// Juju's line depends on how many clues matched.
  (String, String) _notQuiteLine(FeedCheck r, bool knownWord) {
    final passed = <_Clue>[];
    final missed = <_Clue>[];
    for (var i = 0; i < _clues.length; i++) {
      (i < r.results.length && r.results[i] ? passed : missed).add(_clues[i]);
    }
    if (passed.isEmpty || missed.isEmpty) {
      final last = _clues.isEmpty ? null : _clues.last;
      return (
        knownWord
            ? 'Hee hee, that\'s a…'
            : 'Hee hee, I can\'t eat a ${r.object}!',
        last == null
            ? 'Look at the 3 words again!'
            : 'Can you find something that is ${last.english}?',
      );
    }
    final yes = passed.map((c) => c.english).join(' and ');
    final no = missed.map((c) => c.english).join(' or ');
    return ('So close!', "It's $yes, but not $no.");
  }

  Widget _notQuiteView(FeedCheck r) {
    final w = huntWordByEnglish(r.object);
    final (text, sub) = _notQuiteLine(r, w != null);
    return Column(children: [
      _bubble(
        text,
        sub,
        onListen: () =>
            AudioService.instance.playAsset('juju/juju_en_great_trying.mp3'),
        extra: w == null
            ? null
            : Row(children: [
                InkWell(
                  onTap: () => playWord(w),
                  child: arabicLine(str(w.arabicWord),
                      size: 30, color: AppColors.highlight),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('(${str(w.englishWord).toLowerCase()})',
                      style: AppTheme.english(
                          size: 15,
                          weight: FontWeight.w700,
                          color: AppColors.muted)),
                ),
              ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: FeedJujuDesert(
          mood: FeedMood.notQuite,
          food: _photoBite(),
          foodSpot: FoodSpot.sand,
          jujuBuilder: _jujuFor,
        ),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < _clues.length; i++)
        _ruleRow(_clues[i], i < r.results.length && r.results[i]),
      const SizedBox(height: 6),
      GameButton(
          label: 'Try again', icon: Icons.photo_camera_rounded, onTap: _snap),
    ]);
  }

  Widget _yumView(FeedCheck r) {
    final w = huntWordByEnglish(r.object);
    final answers = _riddle['answers'];
    final ans = (w != null && answers is Map) ? answers[str(w.id)] : null;
    final sentence = ans is Map ? ans['sentence'] : null;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Yum yum!',
            textAlign: TextAlign.center,
            style: AppTheme.english(
                size: 28,
                weight: FontWeight.w800,
                color: AppColors.goodShadow)),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 140, child: _photoBox(height: 140)),
          const SizedBox(width: 12),
          Expanded(
            child: w == null
                ? Text(r.object,
                    style: AppTheme.english(size: 22, weight: FontWeight.w800))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(children: [
                          Flexible(
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: arabicLine(str(w.arabicWord),
                                      size: 40, color: AppColors.highlight))),
                          const SizedBox(width: 8),
                          RoundIcon(
                              icon: Icons.volume_up_rounded,
                              label: 'Hear the word',
                              onTap: () => playWord(w),
                              color: AppColors.accent,
                              shadow: AppColors.accentShadow,
                              size: 48),
                        ]),
                        Text(str(w.englishWord),
                            style: AppTheme.english(
                                size: 16,
                                weight: FontWeight.w700,
                                color: AppColors.muted)),
                      ]),
          ),
        ]),
        if (sentence is Map) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: AppColors.line, offset: Offset(0, 4))
              ],
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      arabicLine(str(sentence['arabic']), size: 30),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(str(sentence['english']),
                            style: AppTheme.english(
                                size: 15,
                                weight: FontWeight.w700,
                                color: AppColors.muted)),
                      ),
                    ]),
              ),
              const SizedBox(width: 8),
              RoundIcon(
                icon: Icons.volume_up_rounded,
                label: 'Hear the sentence',
                color: AppColors.accent,
                shadow: AppColors.accentShadow,
                onTap: () async {
                  final a = str(sentence['audio']);
                  if (a.isNotEmpty) {
                    await AudioService.instance.playAsset(a);
                  } else if (w != null) {
                    // word-by-word from existing clips until full-sentence audio exists
                    await playWord(w);
                    final col = ans is Map ? str(ans['colour']) : '';
                    if (col.isNotEmpty) {
                      await playColour(col, feminine: w.isFeminine == true);
                    }
                  }
                },
              ),
            ]),
          ),
        ],
        if (ans is Map && str(ans['fact']).isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.tip, borderRadius: BorderRadius.circular(24)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_rounded,
                  color: AppColors.accentShadow, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("JUJU'S FUN FACT",
                          style: AppTheme.english(
                              size: 12,
                              weight: FontWeight.w800,
                              color: AppColors.muted)),
                      Text(str(ans['fact']),
                          style: AppTheme.english(
                              size: 16, weight: FontWeight.w700)),
                    ]),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        GameButton(
            label: 'Next riddle',
            icon: Icons.arrow_forward_rounded,
            onTap: _next),
      ]),
    );
  }

  Widget _couldNotCheckView() {
    return Column(children: [
      _photoBox(),
      const SizedBox(height: 16),
      const JujuSays(
        pose: JujuPose.sleepy,
        text: 'Oops, I was a bit sleepy!',
        sub: "I couldn't check, but thank you for the snack!",
      ),
      const Spacer(),
      GameButton(
          label: 'Next riddle',
          icon: Icons.arrow_forward_rounded,
          onTap: _next),
    ]);
  }
}
