// Shared loading screen: a 3-pair picture–word match while Muse Spark works.
// Usage:  final result = await waitWithMatch(context, MetaGames.instance.feedCheck(...),
//                                           message: "I'm checking your food…");
// Fast results (under ~1.2 s) skip the game. When the result is ready a glowing
// "Juju's ready!" button appears; the child can finish the round first.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/audio_index.dart';
import '../data/repository.dart';
import '../services/progress.dart';
import '../theme/app_theme.dart';
import 'juju.dart';

class MatchItem {
  final String id;
  final String arabic;
  final String sticker; // asset path
  const MatchItem(this.id, this.arabic, this.sticker);
}

Future<T?> waitWithMatch<T>(BuildContext context, Future<T> work,
    {required String message}) async {
  final quick = await Future.any<bool>([
    work.then((_) => true),
    Future<bool>.delayed(const Duration(milliseconds: 1200), () => false),
  ]);
  if (quick || !context.mounted) return work;
  return Navigator.of(context).push<T>(PageRouteBuilder<T>(
    opaque: true,
    pageBuilder: (_, __, ___) =>
        LoadingMatchScreen<T>(work: work, message: message),
    transitionsBuilder: (_, a, __, child) =>
        FadeTransition(opacity: a, child: child),
  ));
}

String _s(Object? v) => v?.toString() ?? '';

List<MatchItem> matchPool() {
  final repo = Repository.instance;
  final seen = <String>{};
  final out = <MatchItem>[];
  void add(String id, String arabic, String sticker) {
    if (sticker.isEmpty || arabic.isEmpty || !seen.add(arabic)) return;
    out.add(MatchItem(
        id,
        arabic,
        sticker.startsWith('assets/')
            ? sticker
            : 'assets/images/$sticker.webp'));
  }

  for (final w in repo.lessonWordsFor(ProgressService.instance.currentLetter)) {
    add(_s(w.id), _s(w.arabic), _s(w.sticker));
  }
  for (final w in repo.huntWords) {
    add(_s(w.id), _s(w.arabicWord), _s(w.sticker));
  }
  return out;
}

class LoadingMatchScreen<T> extends StatefulWidget {
  final Future<T> work;
  final String message;
  const LoadingMatchScreen(
      {super.key, required this.work, required this.message});

  @override
  State<LoadingMatchScreen<T>> createState() => _LoadingMatchScreenState<T>();
}

class _LoadingMatchScreenState<T> extends State<LoadingMatchScreen<T>> {
  final _rng = Random();
  late final List<MatchItem> _pool = matchPool();
  List<MatchItem> _pics = [];
  List<MatchItem> _words = [];
  final Set<String> _matched = {};
  String? _selected;
  String? _miss;
  bool _ready = false;
  T? _result;

  @override
  void initState() {
    super.initState();
    _newRound();
    widget.work.then((v) {
      if (!mounted) return;
      setState(() {
        _result = v;
        _ready = true;
      });
    });
  }

  void _newRound() {
    final p = List<MatchItem>.of(_pool)..shuffle(_rng);
    final pick = p.take(3).toList();
    setState(() {
      _matched.clear();
      _selected = null;
      _pics = List.of(pick)..shuffle(_rng);
      _words = List.of(pick)..shuffle(_rng);
    });
  }

  void _tapWord(MatchItem w) {
    if (_matched.contains(w.id) || _selected == null) return;
    if (_selected == w.id) {
      AudioIndex.instance.playWord(w.arabic, sticker: _id(w.sticker));
      setState(() {
        _matched.add(w.id);
        _selected = null;
      });
      if (_matched.length == _pics.length) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && !_ready) _newRound();
        });
      }
    } else {
      setState(() => _miss = w.id);
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _miss = null);
      });
    }
  }

  static String _id(String path) {
    final n = path.split('/').last;
    final d = n.lastIndexOf('.');
    return d > 0 ? n.substring(0, d) : n;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(children: [
              Row(children: [
                const Juju(
                    pose: JujuPose.thinking,
                    size: 84,
                    motion: JujuMotion.wiggle),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(color: AppColors.line, offset: Offset(0, 3))
                      ],
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.message,
                              style: AppTheme.english(
                                  size: 17, weight: FontWeight.w800)),
                          Text('Match these while you wait!',
                              style: AppTheme.english(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted)),
                        ]),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: _ready
                    ? Container(height: 14, color: AppColors.accent)
                    : const LinearProgressIndicator(
                        minHeight: 14,
                        color: AppColors.accent,
                        backgroundColor: AppColors.line),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(color: AppColors.line, offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(children: [
                        for (final p in _pics) Expanded(child: _picTile(p)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(children: [
                        for (final w in _words) Expanded(child: _wordTile(w)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _ready
                    ? GestureDetector(
                        key: const ValueKey('ready'),
                        onTap: () => Navigator.of(context).pop(_result),
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radius),
                            boxShadow: const [
                              BoxShadow(
                                  color: AppColors.accentShadow,
                                  offset: Offset(0, 6)),
                              BoxShadow(color: AppColors.tip, spreadRadius: 6),
                            ],
                          ),
                          child: Center(
                            child: Text("Juju's ready! See it",
                                style: AppTheme.english(
                                    size: 22, weight: FontWeight.w800)),
                          ),
                        ),
                      )
                    : const SizedBox(key: ValueKey('wait'), height: 72),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _picTile(MatchItem p) {
    final done = _matched.contains(p.id);
    final sel = _selected == p.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: done ? null : () => setState(() => _selected = p.id),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: done ? 0.5 : 1,
          child: Container(
            decoration: BoxDecoration(
              color:
                  done ? AppColors.good.withOpacity(0.15) : AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: sel
                      ? AppColors.blue
                      : (done ? AppColors.good : AppColors.line),
                  width: sel ? 4 : 3),
            ),
            child: Center(
              child: Image.asset(p.sticker,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined,
                      size: 40, color: AppColors.muted)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordTile(MatchItem w) {
    final done = _matched.contains(w.id);
    final miss = _miss == w.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: () => _tapWord(w),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 120),
          offset: miss ? const Offset(0.04, 0) : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: done ? 0.5 : 1,
            child: Container(
              decoration: BoxDecoration(
                color:
                    done ? AppColors.good.withOpacity(0.15) : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: done ? AppColors.good : AppColors.line, width: 3),
              ),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(w.arabic,
                            style: AppTheme.arabic(
                                size: 34, weight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  if (done) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_rounded,
                        color: AppColors.goodShadow, size: 26),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
