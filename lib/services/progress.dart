import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';

/// The 4 skills, in hub order.
const skillOrder = ['listen', 'speak', 'read', 'write'];

class GalleryItem {
  GalleryItem({required this.wordId, this.story, DateTime? addedAt})
      : addedAt = addedAt ?? DateTime.now();
  final String wordId;
  final Story? story; // null = sticker only
  final DateTime addedAt;

  Json toJson() => {
        'word_id': wordId,
        'story': story?.toJson(),
        'added_at': addedAt.toIso8601String(),
      };

  factory GalleryItem.fromJson(Json j) => GalleryItem(
        wordId: j['word_id'] as String,
        story: j['story'] is Map
            ? Story.fromJson(Json.from(j['story'] as Map))
            : null,
        addedAt: DateTime.tryParse(j['added_at'] as String? ?? ''),
      );
}

/// One board on the writing wall: Juju board pose + sticker + the child's own writing.
class WritingEntry {
  WritingEntry({
    required this.letter,
    required this.target,
    required this.imagePath,
    required this.board,
    this.wordId,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final String letter;
  final String target; // the letter or word written (with marks)
  final String? wordId; // sticker to show, if a word
  final String imagePath; // the child's drawing (PNG on the device)
  final int board; // 1..3 → JujuPose.board1/2/3
  final DateTime addedAt;

  Json toJson() => {
        'letter': letter,
        'target': target,
        'word_id': wordId,
        'image_path': imagePath,
        'board': board,
        'added_at': addedAt.toIso8601String(),
      };

  factory WritingEntry.fromJson(Json j) => WritingEntry(
        letter: j['letter'] as String,
        target: j['target'] as String? ?? '',
        wordId: j['word_id'] as String?,
        imagePath: j['image_path'] as String,
        board: (j['board'] as num?)?.toInt() ?? 1,
        addedAt: DateTime.tryParse(j['added_at'] as String? ?? ''),
      );
}

/// Stars, skills, gallery, writing wall, passport – saved on the device only.
/// Never stores photos or the child's feelings.
class ProgressService extends ChangeNotifier {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  static const _key = 'progress_v1';
  SharedPreferences? _prefs;

  int stars = 0;
  String currentLetter = Repository.hackathonLetters.first;
  final Map<String, Set<String>> _skills = {};
  final List<GalleryItem> gallery = [];
  final List<WritingEntry> writingWall = [];
  final Set<String> stamps = {'home'}; // passport places that are open
  final Set<String> wordsFound = {};
  final Set<String> daysActive = {};

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final s = _prefs!.getString(_key);
    if (s == null) return;
    try {
      final j = Json.from(jsonDecode(s) as Map);
      stars = (j['stars'] as num?)?.toInt() ?? 0;
      currentLetter = j['current_letter'] as String? ?? currentLetter;
      _skills
        ..clear()
        ..addAll({
          for (final e in Json.from(j['skills'] as Map? ?? {}).entries)
            e.key: Set<String>.from(e.value as List),
        });
      gallery
        ..clear()
        ..addAll((j['gallery'] as List? ?? [])
            .map((e) => GalleryItem.fromJson(Json.from(e as Map))));
      writingWall
        ..clear()
        ..addAll((j['writing'] as List? ?? [])
            .map((e) => WritingEntry.fromJson(Json.from(e as Map))));
      stamps.addAll(List<String>.from(j['stamps'] as List? ?? []));
      wordsFound.addAll(List<String>.from(j['words_found'] as List? ?? []));
      daysActive.addAll(List<String>.from(j['days_active'] as List? ?? []));
    } catch (e) {
      debugPrint('Progress: could not read saved data ($e) – starting fresh');
    }
  }

  Future<void> _save() async {
    daysActive.add(DateTime.now().toIso8601String().substring(0, 10));
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _key,
      jsonEncode({
        'stars': stars,
        'current_letter': currentLetter,
        'skills': {for (final e in _skills.entries) e.key: e.value.toList()},
        'gallery': gallery.map((g) => g.toJson()).toList(),
        'writing': writingWall.map((w) => w.toJson()).toList(),
        'stamps': stamps.toList(),
        'words_found': wordsFound.toList(),
        'days_active': daysActive.toList(),
      }),
    );
  }

  // ---------- stars ----------
  Future<void> addStars([int n = 1]) async {
    stars += n;
    await _save();
  }

  // ---------- letter & skills ----------
  Future<void> setLetter(String letter) async {
    currentLetter = letter;
    await _save();
  }

  bool isSkillDone(String letter, String skill) =>
      _skills[letter]?.contains(skill) ?? false;

  /// done ✓ / next (first unfinished, in hub order) / todo.
  SkillState skillState(String letter, String skill) {
    if (isSkillDone(letter, skill)) return SkillState.done;
    final next =
        skillOrder.firstWhere((s) => !isSkillDone(letter, s), orElse: () => '');
    return next == skill ? SkillState.next : SkillState.todo;
  }

  /// All 4 skills done → letter badge.
  bool hasBadge(String letter) =>
      skillOrder.every((s) => isSkillDone(letter, s));

  Future<void> markSkillDone(String letter, String skill) async {
    (_skills[letter] ??= {}).add(skill);
    await _save();
  }

  // ---------- treasure hunt ----------
  Future<void> markFound(String wordId) async {
    wordsFound.add(wordId);
    await _save();
  }

  Future<void> addToGallery(String wordId, {Story? story}) async {
    gallery.removeWhere(
        (g) => g.wordId == wordId && g.story == null && story != null);
    gallery.add(GalleryItem(wordId: wordId, story: story));
    wordsFound.add(wordId);
    await _save();
  }

  Future<void> openStamp(String place) async {
    stamps.add(place);
    await _save();
  }

  // ---------- writing wall ----------
  /// Saves the child's drawing as a PNG on the device and adds a board.
  Future<WritingEntry> addWriting({
    required String letter,
    required String target,
    required Uint8List png,
    String? wordId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/writing');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file =
        File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(png, flush: true);

    final entry = WritingEntry(
      letter: letter,
      target: target,
      wordId: wordId,
      imagePath: file.path,
      board: writingWall.length % 3 + 1,
    );
    writingWall.add(entry);
    await _save();
    return entry;
  }

  // ---------- parents ----------
  /// Plain facts for the weekly report (MetaText.parentReport).
  String summary() {
    final b = StringBuffer()
      ..writeln('Stars: $stars. Days active: ${daysActive.length}.')
      ..writeln('This week\'s letter: $currentLetter.');
    for (final l in Repository.hackathonLetters) {
      final done = skillOrder.where((s) => isSkillDone(l, s)).toList();
      if (done.isNotEmpty) b.writeln('Letter $l: ${done.join(', ')} done.');
    }
    final names = wordsFound
        .map((id) => Repository.instance.huntWord(id)?.englishWord ?? id)
        .join(', ');
    if (names.isNotEmpty) b.writeln('Words found at home: $names.');
    b.writeln('Writings on the wall: ${writingWall.length}.');
    return b.toString();
  }

  Future<void> resetAll() async {
    for (final w in writingWall) {
      try {
        File(w.imagePath).deleteSync();
      } catch (_) {}
    }
    stars = 0;
    currentLetter = Repository.hackathonLetters.first;
    _skills.clear();
    gallery.clear();
    writingWall.clear();
    stamps
      ..clear()
      ..add('home');
    wordsFound.clear();
    daysActive.clear();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_key);
    notifyListeners();
  }
}
