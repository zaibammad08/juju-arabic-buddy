// lib/widgets/writing_board.dart
//
// Shared by Screen 14 (Writing wall) and Screen 2 (My Letter hub):
//   • JujuBoard        – Juju's board pose + the child's OWN writing on it
//                        (same layout as Screen 6's celebration)
//   • WritingItem      – one saved writing, read from ProgressService.writingWall
//                        (PNG as bytes, base64, absolute path OR a file name
//                        inside the app documents folder)
//   • WritingWallStrip – small "My writing wall" row for the letter hub

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart' show Routes;
import '../theme/app_theme.dart';
import '../services/progress.dart';
import 'juju.dart';

// ======================================================================
// JujuBoard
// ======================================================================

class JujuBoard extends StatelessWidget {
  const JujuBoard({
    super.key,
    required this.board,
    this.writing,
    this.sticker,
    this.size = 200,
    this.animateSticker = true,
  });

  final int board; // 1, 2 or 3
  final ImageProvider? writing; // the child's own transparent PNG
  final String? sticker; // asset path; null for letter-only writing
  final double size; // size of the Juju image (widget is size + 40 wide)
  final bool animateSticker;

  /// COPY of `_boardRects` in letter_write_screen.dart – keep the two equal.
  static const Map<int, Rect> boardArea = {
    1: Rect.fromLTWH(0.50, 0.16, 0.44, 0.40),
    2: Rect.fromLTWH(0.22, 0.50, 0.56, 0.32),
    3: Rect.fromLTWH(0.30, 0.50, 0.40, 0.26),
  };

  /// Which board to show. The neck board (3) is too small for words, so a
  /// word on board 3 moves to board 1 or 2 (always the same one for the same
  /// word). Screen 6 calls this too, so the wall matches the celebration.
  static int boardFor(int board,
      {required bool isLetter, required String text}) {
    final b = (board >= 1 && board <= 3) ? board : 1;
    if (b != 3 || isLetter) return b;
    return text.runes.length.isEven ? 1 : 2;
  }

  @override
  Widget build(BuildContext context) {
    final b = boardArea.containsKey(board) ? board : 1;
    final rect = boardArea[b]!;
    final pose = switch (b) {
      2 => JujuPose.board2,
      3 => JujuPose.board3,
      _ => JujuPose.board1,
    };

    return SizedBox(
      width: size + 40,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 20, top: 0, child: Juju(pose: pose, size: size)),
          Positioned(
            left: 20 + rect.left * size,
            top: rect.top * size,
            width: rect.width * size,
            height: rect.height * size,
            child: Padding(
              padding: EdgeInsets.all(size < 150 ? 3 : 6),
              // Only the child's writing – never typed Arabic. If the picture
              // can't be found, a pencil shows instead.
              child: writing != null
                  ? Image(
                      image: writing!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _missing(),
                    )
                  : _missing(),
            ),
          ),
          if (sticker != null)
            Positioned(left: 0, bottom: 0, child: _sticker()),
        ],
      ),
    );
  }

  Widget _missing() => const FittedBox(
        child: Opacity(
            opacity: 0.35, child: Text('✏️', style: TextStyle(fontSize: 40))),
      );

  Widget _sticker() {
    final s = size * 0.30;
    final img = SizedBox(
      width: s,
      height: s,
      child: Image.asset(sticker!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    );
    if (!animateSticker) return img;
    return img
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: 0, end: -14, duration: 650.ms, curve: Curves.easeInOut)
        .then()
        .rotate(begin: -0.02, end: 0.02, duration: 400.ms);
  }
}

// ======================================================================
// WritingItem
// ======================================================================

class WritingItem {
  WritingItem({
    required this.letter,
    required this.target,
    required this.wordId,
    required this.board,
    required this.image,
    required this.when,
    required this.order,
  });

  final String letter;
  final String target;
  final String? wordId;
  final int board;
  final ImageProvider? image;
  final DateTime? when;
  final int order;

  bool get isLetterOnly =>
      wordId == null || wordId!.isEmpty || wordId == letter || target == letter;

  String? get sticker => isLetterOnly ? null : 'assets/images/$wordId.webp';

  // ---- app documents folder (for PNGs saved as a file name) ----
  static String? _docs;
  static Future<void>? _docsLoading;

  /// Call once (e.g. in initState) and setState when it completes.
  static Future<void> init() {
    return _docsLoading ??= () async {
      try {
        _docs = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {}
    }();
  }

  static bool get ready => _docs != null;

  /// All writings, newest first; [letter] filters to one letter.
  static List<WritingItem> all({String? letter}) {
    final list = <WritingItem>[];
    var i = 0;
    for (final e in ProgressService.instance.writingWall) {
      final w = from(e, i++);
      if (w == null) continue;
      if (letter != null && w.letter != letter) continue;
      list.add(w);
    }
    list.sort((a, b) {
      if (a.when != null && b.when != null) return b.when!.compareTo(a.when!);
      return b.order.compareTo(a.order);
    });
    return list;
  }

  static T? _try<T>(dynamic Function() f) {
    try {
      final v = f();
      return v is T ? v : null;
    } catch (_) {
      return null;
    }
  }

  static bool _loggedOnce = false;

  static WritingItem? from(dynamic e, int order) {
    final Map? json =
        e is Map ? e : (_try<Map>(() => e.toJson()) ?? _try<Map>(() => e.raw));

    dynamic pick(List<String> keys, List<dynamic Function()> getters) {
      for (final g in getters) {
        final v = _try<Object>(g);
        if (v != null) return v;
      }
      if (json != null) {
        for (final k in keys) {
          if (json[k] != null) return json[k];
        }
      }
      return null;
    }

    final letter = '${pick(['letter'], [() => e.letter]) ?? ''}';
    final target =
        '${pick(['target', 'word', 'text'], [() => e.target]) ?? letter}';
    final wordIdRaw = pick(['wordId', 'word_id'], [() => e.wordId]);
    final boardRaw = pick(['board'], [() => e.board]);
    final whenRaw = pick(
        ['createdAt', 'created_at', 'date', 'time', 'at', 'when'],
        [() => e.createdAt, () => e.date, () => e.at]);

    // the child's picture: try the usual names, then anything that looks like one
    ImageProvider? image;
    final candidates = <dynamic>[
      _try<Object>(() => e.png),
      _try<Object>(() => e.pngPath),
      _try<Object>(() => e.pngFile),
      _try<Object>(() => e.path),
      _try<Object>(() => e.file),
      _try<Object>(() => e.fileName),
      _try<Object>(() => e.imagePath),
      _try<Object>(() => e.bytes),
      _try<Object>(() => e.pngBytes),
      if (json != null)
        for (final k in const [
          'png',
          'pngPath',
          'png_path',
          'pngFile',
          'path',
          'file',
          'fileName',
          'file_name',
          'image',
          'imagePath',
          'image_path',
          'pngBase64',
          'bytes',
        ])
          json[k],
      if (json != null) ...json.values,
    ];
    for (final c in candidates) {
      image = _image(c);
      if (image != null) break;
    }

    if (kDebugMode && !_loggedOnce) {
      _loggedOnce = true;
      debugPrint('WritingWall: first entry = ${json ?? e} '
          '→ picture ${image != null ? 'FOUND' : 'NOT FOUND'} (docs: $_docs)');
    }

    if (letter.isEmpty && target.isEmpty && image == null) return null;

    return WritingItem(
      letter: letter,
      target: target,
      wordId: wordIdRaw?.toString(),
      board: JujuBoard.boardFor(
        boardRaw is int ? boardRaw : int.tryParse('$boardRaw') ?? 1,
        isLetter: wordIdRaw == null ||
            '$wordIdRaw'.isEmpty ||
            '$wordIdRaw' == letter ||
            target == letter,
        text: target,
      ),
      image: image,
      when: _date(whenRaw),
      order: order,
    );
  }

  static ImageProvider? _image(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List) return v.length > 64 ? MemoryImage(v) : null;
    if (v is List<int>) {
      return v.length > 64 ? MemoryImage(Uint8List.fromList(v)) : null;
    }
    if (v is List && v.length > 64 && v.first is int) {
      return MemoryImage(Uint8List.fromList(v.cast<int>()));
    }
    if (v is File) return v.existsSync() ? FileImage(v) : null;
    if (v is! String || v.isEmpty) return null;

    var s = v.trim();
    if (s.startsWith('data:')) s = s.substring(s.indexOf(',') + 1);

    final looksLikeFile = s.startsWith('/') ||
        s.startsWith('file:') ||
        s.contains('\\') ||
        RegExp(r'\.(png|jpg|jpeg|webp)$', caseSensitive: false).hasMatch(s);
    if (looksLikeFile) {
      final clean = s.replaceFirst('file://', '');
      final name = clean.split(RegExp(r'[\\/]')).last;
      final tries = <String>[
        clean,
        if (_docs != null && !clean.startsWith('/')) '$_docs/$clean',
        if (_docs != null) '$_docs/$name',
        if (_docs != null) '$_docs/writing/$name',
        if (_docs != null) '$_docs/writings/$name',
        if (_docs != null) '$_docs/writing_wall/$name',
      ];
      for (final p in tries) {
        final f = File(p);
        if (f.existsSync()) return FileImage(f);
      }
      return null;
    }

    // base64 PNG (long string only – short strings are names/ids)
    if (s.length > 200) {
      try {
        final bytes = base64Decode(s);
        if (bytes.length > 64) return MemoryImage(bytes);
      } catch (_) {}
    }
    return null;
  }

  static DateTime? _date(dynamic v) {
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

// ======================================================================
// WritingWallStrip – for the My Letter hub (Screen 2)
// ======================================================================

/// "🧱 My writing wall" card: this letter's boards in a row (newest first),
/// "See all" → Screen 14 opened on this letter. Empty: an invitation to write.
class WritingWallStrip extends StatefulWidget {
  const WritingWallStrip({super.key, required this.letter});

  final String letter;

  @override
  State<WritingWallStrip> createState() => _WritingWallStripState();
}

class _WritingWallStripState extends State<WritingWallStrip> {
  @override
  void initState() {
    super.initState();
    if (!WritingItem.ready) {
      WritingItem.init().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _openWall() => Navigator.pushNamed(context, Routes.writingWall,
      arguments: widget.letter);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) {
        final items = WritingItem.all(letter: widget.letter);
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: AppColors.line, offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('🧱 My writing wall',
                    style: AppTheme.english(size: 18, weight: FontWeight.w800)),
                const Spacer(),
                if (items.isNotEmpty)
                  InkWell(
                    onTap: _openWall,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      child: Text('See all ${items.length} →',
                          style: AppTheme.english(
                              size: 15,
                              color: AppColors.blue,
                              weight: FontWeight.w800)),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              if (items.isEmpty)
                _empty()
              else
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => InkWell(
                      onTap: _openWall,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: JujuBoard(
                          board: items[i].board,
                          writing: items[i].image,
                          sticker: items[i].sticker,
                          size: 112,
                          animateSticker: false,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, Routes.letterWrite,
          arguments: widget.letter),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: BoxConstraints(minHeight: AppTheme.minTap.toDouble()),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Juju(pose: JujuPose.pencil, size: 56),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Write and your writing hangs here!',
                style: AppTheme.english(
                    size: 15, color: AppColors.muted, weight: FontWeight.w700)),
          ),
          Text(widget.letter,
              textDirection: TextDirection.rtl,
              style: AppTheme.arabic(
                  size: 30,
                  color: AppColors.highlight,
                  weight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
