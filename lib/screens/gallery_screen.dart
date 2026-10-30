// Screen 13 – My Arabic Room (gallery_screen.dart)
// Every word the child found: sticker in its gender frame (blue M / orange F + ة badge),
// tinted with the colour the child chose, a 📖 badge when it has a story.
// Tap a line -> it plays and opens word-by-word English (frame words from the 'gloss'
// field in sentence_templates.json, adjectives/colours from their JSON, the noun from the word).
// Tap a card -> the word's 5 everyday sentences (pre-recorded, from sentence_bank) + its story.
// Arabic/English toggle, "N of 65 found" progress + Room Explorer badge at 10,
// "Find more!" tile -> camera. Tap a card -> word + its story (tap a line to hear it).
//
// Reads ProgressService.gallery / wordsFound defensively (Map, List, ids or objects),
// so it works with whatever addToGallery() / markFound() store.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../data/repository.dart';
import '../data/arabic_forms.dart';
import '../data/audio_index.dart';
import '../services/audio.dart';
import '../services/progress.dart';
import '../widgets/juju.dart';
import '../widgets/big_button.dart';
import '../widgets/arabic_text.dart';

/// One story line, whatever form it was saved in.
class _Line {
  final String arabic, audioText, english, phonetic;
  final String audio; // pre-made mp3 (relative to assets/audio/), '' = live TTS
  const _Line(this.arabic, this.audioText, this.english, this.phonetic,
      [this.audio = '']);
}

/// One card in the room.
class _Entry {
  final HuntWord word;
  final List<_Line> story; // empty = found, no story yet
  final String? colourId;
  const _Entry(this.word, this.story, this.colourId);
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const _explorerAt = 10;

  // Display tint only (same as Screen 10).
  static const Map<String, Color> _swatch = {
    'red': Color(0xFFE53935),
    'blue': Color(0xFF1E88E5),
    'green': Color(0xFF43A047),
    'yellow': Color(0xFFFDD835),
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF263238),
    'brown': Color(0xFF8D6E63),
    'orange': Color(0xFFFB8C00),
    'pink': Color(0xFFF06292),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
  };

  bool _arabic = true;
  bool _greeted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_greeted) return;
    _greeted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AudioService.instance.say(
        _entries().isEmpty
            ? "Your Arabic room is empty. Let's go hunting!"
            : "This is your Arabic room! Tap a picture to hear it.",
        voice: TtsVoice.jujuEnglish,
      );
    });
  }

  @override
  void dispose() {
    AudioService.instance.stop();
    super.dispose();
  }

  // ----------------------------------------------------------------- data

  List<_Entry> _entries() {
    final repo = Repository.instance;
    final p = ProgressService.instance;
    final byId = <String, _Entry>{};

    void add(String? id, Object? story, String? colour) {
      if (id == null || id.isEmpty) return;
      final w = repo.huntWord(id);
      if (w == null) return;
      final lines = _readLines(story);
      final old = byId[id];
      // Keep the version with a story (latest story wins).
      if (old == null || lines.isNotEmpty) {
        byId[id] = _Entry(
            w,
            lines.isNotEmpty ? lines : (old?.story ?? const []),
            colour ?? _storyColour(story) ?? old?.colourId);
      }
    }

    void addAny(Object? e, [String? keyId]) {
      if (e == null) {
        add(keyId, null, null);
      } else if (e is String) {
        add(keyId ?? e, null, null);
      } else if (e is Story) {
        add(keyId ?? e.wordId, e, e.colour);
      } else if (e is Map) {
        add(
            (e['wordId'] ?? e['word_id'] ?? e['id'] ?? keyId)?.toString(),
            e['story'] ?? (e['lines'] != null ? e : null),
            e['colour']?.toString());
      } else {
        final d = e as dynamic;
        String? id;
        Object? story;
        try {
          id = d.wordId as String?;
        } catch (_) {}
        try {
          story = d.story;
        } catch (_) {}
        add(id ?? keyId, story, null);
      }
    }

    final dynamic g = p.gallery;
    if (g is Map) {
      g.forEach((k, v) => addAny(v, k.toString()));
    } else if (g is Iterable) {
      for (final e in g) addAny(e);
    }
    // Words found but not (yet) added with a story, e.g. after Skip.
    final dynamic f = p.wordsFound;
    if (f is Iterable) {
      for (final id in f) if (!byId.containsKey('$id')) add('$id', null, null);
    } else if (f is Map) {
      for (final id in f.keys)
        if (!byId.containsKey('$id')) add('$id', null, null);
    }
    return byId.values.toList().reversed.toList(); // newest first
  }

  int _foundCount(int cards) {
    final dynamic f = ProgressService.instance.wordsFound;
    final n =
        f is int ? f : (f is Iterable ? f.length : (f is Map ? f.length : 0));
    return n > cards ? n : cards;
  }

  String? _storyColour(Object? s) {
    if (s is Story) return s.colour;
    if (s is Map) return s['colour']?.toString();
    return null;
  }

  List<_Line> _readLines(Object? s) {
    List<dynamic>? raw;
    if (s is Story) {
      return [
        for (final l in s.lines)
          _Line(l.arabic, l.audioText, l.english, l.phonetic),
      ];
    }
    if (s is Map) raw = s['lines'] as List?;
    if (s is List) raw = s;
    if (raw == null) return const [];
    return [
      for (final l in raw)
        if (l is SentenceLine)
          _Line(
              l.arabic, l.audioText, l.english, l.phonetic, _audioPath(l.audio))
        else if (l is Map)
          _Line(
            '${l['arabic'] ?? ''}',
            '${l['audio_text'] ?? l['audioText'] ?? l['arabic'] ?? ''}',
            '${l['english'] ?? ''}',
            '${l['phonetic'] ?? ''}',
            _audioPath(l['audio']?.toString()),
          ),
    ];
  }

  // ----------------------------------------------------------------- word-by-word

  Map<String, String>? _frame; // whole frame words (أَنَا, أَرَى, الْبَابَ…)
  final Map<String, String> _prefix = {}; // joined prefixes (بِ -> with)
  final Map<String, String> _adj = {};

  String _norm(String t) => ArabicForms.normalise(ArabicForms.strip(t))
      .replaceAll(RegExp(r'[؟?،,.!]'), '')
      .trim();

  String _noAl(String k) =>
      (k.startsWith('ال') && k.length > 3) ? k.substring(2) : k;

  void _loadGloss() {
    if (_frame != null) return;
    _frame = {};
    final repo = Repository.instance;
    final dynamic templates = repo.sentenceTemplates;
    if (templates is Iterable) {
      for (final t in templates) {
        Map? m;
        if (t is Map) {
          m = t;
        } else {
          try {
            m = (t as dynamic).raw as Map?;
          } catch (_) {}
        }
        final g = m?['gloss'];
        if (g is Map) {
          g.forEach((ar, en) {
            final k = _norm('$ar');
            if (k.isEmpty) return;
            (k.length == 1 ? _prefix : _frame!)[k] = '$en';
          });
        }
      }
    }
    for (final a in repo.adjectives) {
      _adj[_noAl(_norm(a.m))] = a.en;
      _adj[_noAl(_norm(a.f))] = a.en;
    }
    for (final c in repo.colours) {
      _adj[_noAl(_norm(c.m))] = c.en;
      _adj[_noAl(_norm(c.f))] = c.en;
    }
  }

  /// [(arabic, english)] chunks for one line; nouns (also two-word ones) stay together.
  List<(String, String)> _gloss(String arabic, HuntWord w) {
    _loadGloss();
    final nounKeys =
        w.arabicWord.split(RegExp(r'\s+')).map((t) => _noAl(_norm(t))).toSet();
    final noun = w.englishWord.toLowerCase();
    final tokens =
        arabic.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final out = <(String, String)>[];

    // Collects a noun group starting at i (first token may carry a prefix like بِ).
    int nounGroup(int i, String lead, bool definite) {
      final group = [tokens[i]];
      var j = i + 1;
      while (j < tokens.length && nounKeys.contains(_noAl(_norm(tokens[j])))) {
        if (_norm(tokens[j]).startsWith('ال')) definite = true;
        group.add(tokens[j]);
        j++;
      }
      out.add((group.join(' '), '$lead${definite ? 'the ' : ''}$noun'));
      return j;
    }

    var i = 0;
    while (i < tokens.length) {
      final k0 = _norm(tokens[i]);
      final k = _noAl(k0);
      final frame = _frame![k0];
      if (frame != null) {
        out.add((tokens[i], frame));
        i++;
      } else if (nounKeys.contains(k)) {
        i = nounGroup(i, '', k0.startsWith('ال'));
      } else if (_adj[k] != null) {
        out.add((tokens[i], _adj[k]!));
        i++;
      } else {
        final p = _prefix.keys.where((p) =>
            k0.startsWith(p) &&
            nounKeys.contains(_noAl(k0.substring(p.length))));
        if (p.isNotEmpty) {
          final rest = k0.substring(p.first.length);
          i = nounGroup(i, '${_prefix[p.first]} ', rest.startsWith('ال'));
        } else {
          out.add((tokens[i], ''));
          i++;
        }
      }
    }
    if (arabic.trim().endsWith('؟') && out.isNotEmpty) {
      final last = out.removeLast();
      out.add((last.$1, '${last.$2}?'));
    }
    return out;
  }

  /// "lamp_s1.mp3" -> "sentences/lamp_s1.mp3" (paths are relative to assets/audio/).
  String _audioPath(String? a) {
    if (a == null || a.isEmpty) return '';
    return a.contains('/') ? a : 'sentences/$a';
  }

  /// The word's 5 everyday sentences from sentence_bank.json.
  List<_Line> _bankLines(HuntWord w) {
    final entry = Repository.instance.bankEntry(w.id);
    if (entry == null) return const [];
    return _readLines(entry.sentences);
  }

  int _playToken = 0;

  Future<void> _playLine(_Line l) {
    _playToken++; // stops a running "Play all"
    return _sayLine(l);
  }

  Future<void> _sayLine(_Line l) => l.audio.isNotEmpty
      ? AudioService.instance
          .playOrSay(asset: l.audio, text: l.audioText, voice: TtsVoice.lesson)
      : AudioService.instance.say(l.audioText, voice: TtsVoice.lesson);

  Future<void> _playAll(List<_Line> lines) async {
    final token = ++_playToken;
    await AudioService.instance.stop();
    for (final l in lines) {
      if (token != _playToken || !mounted) return;
      if (l.audio.isNotEmpty) {
        await AudioService.instance.playAsset(l.audio, wait: true);
      } else {
        await AudioService.instance.say(l.audioText, voice: TtsVoice.lesson);
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  String _stickerPath(HuntWord w) {
    final s = w.sticker;
    if (s.isEmpty) return 'assets/images/${w.id}.webp';
    if (s.startsWith('assets/')) return s;
    if (s.contains('/')) return 'assets/$s';
    return 'assets/images/$s';
  }

  // ----------------------------------------------------------------- navigation

  void _back() {
    AudioService.instance.stop();
    var atHub = false;
    Navigator.popUntil(context, (r) {
      if (r.settings.name == Routes.huntHub) atHub = true;
      return atHub || r.isFirst;
    });
    if (!atHub) Navigator.pushNamed(context, Routes.huntHub);
  }

  void _findMore() {
    AudioService.instance.stop();
    Navigator.pushNamed(context, Routes.camera);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: ProgressService.instance,
            builder: (context, _) {
              final entries = _entries();
              final total = Repository.instance.huntWords.length;
              final found = _foundCount(entries.length);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    const SizedBox(height: 10),
                    _progress(found, total),
                    const SizedBox(height: 12),
                    _toggleRow(),
                    const SizedBox(height: 14),
                    if (entries.isEmpty)
                      _empty()
                    else
                      _grid(entries, total - found),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          InkWell(
            onTap: _back,
            customBorder: const CircleBorder(),
            child: Container(
              width: AppTheme.minTap,
              height: AppTheme.minTap,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 30),
            ),
          ),
          Expanded(
            child: Text('My Arabic Room',
                textAlign: TextAlign.center,
                style: AppTheme.english(
                    size: 24, weight: FontWeight.w800, color: AppColors.ink)),
          ),
          Row(children: [
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 28),
            const SizedBox(width: 2),
            Text('${ProgressService.instance.stars}',
                style: AppTheme.english(size: 18, weight: FontWeight.w800)),
          ]),
          const SizedBox(width: 6),
        ],
      );

  Widget _progress(int found, int total) {
    final explorer = found >= _explorerAt;
    final value = total == 0 ? 0.0 : (found / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: AppColors.line, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$found of $total found',
                  style: AppTheme.english(size: 17, weight: FontWeight.w800)),
              const Spacer(),
              Text(
                  explorer
                      ? '🏅 Room Explorer!'
                      : '🏅 Room Explorer at $_explorerAt',
                  style: AppTheme.english(
                      size: 14,
                      weight: FontWeight.w700,
                      color:
                          explorer ? AppColors.goodShadow : AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 12,
              color: AppColors.good,
              backgroundColor: AppColors.line,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow() => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: Row(children: [
              _toggleBtn('عربي', true, arabicFont: true),
              _toggleBtn('English', false),
            ]),
          ),
          const Spacer(),
          _legendDot(AppColors.masculine, 'boy word'),
          const SizedBox(width: 10),
          _legendDot(AppColors.feminine, 'girl word ة'),
        ],
      );

  Widget _toggleBtn(String label, bool arabic, {bool arabicFont = false}) {
    final on = _arabic == arabic;
    return GestureDetector(
      onTap: () => setState(() => _arabic = arabic),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 52, minWidth: 72),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(label,
            style: arabicFont
                ? AppTheme.arabic(
                    size: 20, weight: FontWeight.w700, color: AppColors.ink)
                : AppTheme.english(
                    size: 16, weight: FontWeight.w800, color: AppColors.ink)),
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: AppTheme.english(
                size: 13, color: AppColors.muted, weight: FontWeight.w600)),
      ]);

  Widget _empty() => Column(
        children: [
          const SizedBox(height: 20),
          const Juju(
              pose: JujuPose.camera, size: 160, motion: JujuMotion.bounce),
          const SizedBox(height: 10),
          Text('Nothing here yet!',
              style: AppTheme.english(size: 22, weight: FontWeight.w800)),
          Text('Find things at home and they will live here.',
              textAlign: TextAlign.center,
              style: AppTheme.english(size: 16, color: AppColors.muted)),
          const SizedBox(height: 16),
          BigButton(
              label: 'Start hunting!',
              emoji: '📷',
              style: BigButtonStyle.good,
              expand: true,
              onTap: _findMore),
        ],
      );

  Widget _grid(List<_Entry> entries, int hiding) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
        children: [
          for (var i = 0; i < entries.length; i++)
            _card(entries[i])
                .animate()
                .fadeIn(delay: (40 * i).ms, duration: 250.ms)
                .scale(begin: const Offset(0.9, 0.9), duration: 250.ms),
          _findMoreTile(hiding),
        ],
      );

  Widget _sticker(_Entry e, double size) {
    Widget img = Image.asset(
      _stickerPath(e.word),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Text('🎁', style: TextStyle(fontSize: size * 0.6)),
    );
    final tint = e.colourId == null ? null : _swatch[e.colourId];
    if (tint != null) {
      img = ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.color), child: img);
    }
    return img;
  }

  Widget _card(_Entry e) {
    final w = e.word;
    final frame = w.isFeminine ? AppColors.feminine : AppColors.masculine;
    return Semantics(
      button: true,
      label: w.englishWord,
      child: GestureDetector(
        onTap: () => _open(e),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: frame, width: 4),
            boxShadow: const [
              BoxShadow(color: AppColors.line, offset: Offset(0, 5))
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                child: Column(
                  children: [
                    Expanded(child: Center(child: _sticker(e, 76))),
                    const SizedBox(height: 4),
                    if (_arabic) ...[
                      FittedBox(
                        child: ArabicText(w.arabicWord,
                            size: 22,
                            highlightLetter: w.letter,
                            firstOnly: true),
                      ),
                      Text(w.phonetic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.english(
                              size: 13,
                              color: AppColors.muted,
                              weight: FontWeight.w600)),
                    ] else
                      FittedBox(
                        child: Text(w.englishWord,
                            style: AppTheme.english(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.ink)),
                      ),
                  ],
                ),
              ),
              if (w.isFeminine)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                        color: AppColors.feminineBadge,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('ة',
                        style: AppTheme.arabic(size: 16, color: Colors.white)),
                  ),
                ),
              if (e.story.isNotEmpty)
                const Positioned(
                    top: 2,
                    right: 6,
                    child: Text('📖', style: TextStyle(fontSize: 20))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _findMoreTile(int hiding) => Semantics(
        button: true,
        label: 'Find a new thing',
        child: GestureDetector(
          onTap: _findMore,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.good, width: 3),
              boxShadow: const [
                BoxShadow(color: AppColors.goodShadow, offset: Offset(0, 5))
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📷', style: TextStyle(fontSize: 38)),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text('Find more!',
                      style: AppTheme.english(
                          size: 17,
                          weight: FontWeight.w800,
                          color: AppColors.goodShadow)),
                ),
                Text(
                    hiding > 0
                        ? '$hiding hiding at home'
                        : 'You found them all!',
                    textAlign: TextAlign.center,
                    style: AppTheme.english(size: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      );

  // ----------------------------------------------------------------- detail sheet

  void _open(_Entry e) {
    final w = e.word;
    final bank = _bankLines(w);
    String? open; // which line shows word-by-word ('b0'…'b4', 's0'…'s4')
    AudioIndex.instance.playWord(w.arabicWord, sticker: w.sticker);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => DraggableScrollableSheet(
                expand: false,
                initialChildSize:
                    (bank.isEmpty && e.story.isEmpty) ? 0.55 : 0.9,
                maxChildSize: 0.95,
                builder: (ctx, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 6,
                        decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          border: Border.all(
                              color: w.isFeminine
                                  ? AppColors.feminine
                                  : AppColors.masculine,
                              width: 5),
                        ),
                        child: _sticker(e, 150),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                        child: ArabicText(w.arabicWord,
                            size: 40,
                            highlightLetter: w.letter,
                            firstOnly: true)),
                    Text('${w.phonetic} · ${w.englishWord}',
                        textAlign: TextAlign.center,
                        style: AppTheme.english(
                            size: 17,
                            weight: FontWeight.w700,
                            color: AppColors.muted)),
                    const SizedBox(height: 12),
                    BigButton(
                      label: 'Listen',
                      icon: Icons.volume_up_rounded,
                      style: BigButtonStyle.accent,
                      expand: true,
                      onTap: () => AudioIndex.instance
                          .playWord(w.arabicWord, sticker: w.sticker),
                    ),
                    if (bank.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionHead(
                          '💬 Say it every day',
                          'Use these at home. Tap a line to hear it word by word.',
                          bank),
                      for (var i = 0; i < bank.length; i++)
                        _storyLine(i, bank[i], AppColors.good, w, open == 'b$i',
                            () {
                          _playLine(bank[i]);
                          setSheet(() => open = open == 'b$i' ? null : 'b$i');
                        }),
                    ],
                    if (e.story.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionHead(
                          '📖 My ${w.englishWord.toLowerCase()} story',
                          'The story you made. Tap a line for word by word.',
                          e.story),
                      for (var i = 0; i < e.story.length; i++)
                        _storyLine(
                            i, e.story[i], AppColors.accent, w, open == 's$i',
                            () {
                          _playLine(e.story[i]);
                          setSheet(() => open = open == 's$i' ? null : 's$i');
                        }),
                    ],
                  ],
                ),
              )),
    ).whenComplete(() {
      _playToken++;
      AudioService.instance.stop();
    });
  }

  Widget _sectionHead(String title, String sub, List<_Line> lines) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTheme.english(
                            size: 20, weight: FontWeight.w800)),
                    Text(sub,
                        style:
                            AppTheme.english(size: 14, color: AppColors.muted)),
                  ]),
            ),
            TextButton.icon(
              onPressed: () => _playAll(lines),
              style: TextButton.styleFrom(
                  minimumSize: const Size(64, AppTheme.minTap)),
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.blue, size: 30),
              label: Text('Play all',
                  style: AppTheme.english(
                      size: 15,
                      weight: FontWeight.w800,
                      color: AppColors.blue)),
            ),
          ],
        ),
      );

  Widget _storyLine(int i, _Line l, Color numberColour, HuntWord w, bool open,
          VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTheme.minTap),
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: open ? numberColour : AppColors.line, width: 2),
            ),
            child: Column(children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: numberColour,
                    child: Text('${i + 1}',
                        style: AppTheme.english(
                            size: 16,
                            weight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(l.arabic,
                            textDirection: TextDirection.rtl,
                            style: AppTheme.arabic(
                                size: 24,
                                weight: FontWeight.w700,
                                color: AppColors.ink)),
                        if (l.phonetic.isNotEmpty)
                          Text(l.phonetic,
                              style: AppTheme.english(
                                  size: 14,
                                  color: AppColors.blue,
                                  weight: FontWeight.w600)),
                        Text(l.english,
                            style: AppTheme.english(
                                size: 14, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.volume_up_rounded,
                      color: AppColors.blue),
                ],
              ),
              if (open) ...[
                const SizedBox(height: 10),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (ar, en) in _gloss(l.arabic, w))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.line, width: 2),
                          ),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(ar,
                                textDirection: TextDirection.rtl,
                                style: AppTheme.arabic(
                                    size: 24,
                                    weight: FontWeight.w700,
                                    color: AppColors.ink)),
                            if (en.isNotEmpty)
                              Text(en,
                                  textDirection: TextDirection.ltr,
                                  style: AppTheme.english(
                                      size: 13,
                                      weight: FontWeight.w600,
                                      color: AppColors.muted)),
                          ]),
                        ),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ],
            ]),
          ),
        ),
      );
}
