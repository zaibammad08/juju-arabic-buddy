import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

export 'models.dart';

/// Loads every file in assets/data/ once, at app start (Screen 0).
/// Screens read from Repository.instance – never hard-code Arabic words.
class Repository {
  Repository._();
  static final Repository instance = Repository._();

  /// Letters playable in the hackathon (the founder's 5 home lessons).
  static const hackathonLetters = ['ا', 'ب', 'م', 'د', 'س'];

  /// lessons/<file>.json – ASCII file names are safer than Arabic ones.
  static const lessonFiles = {
    'ا': 'alif',
    'ب': 'baa',
    'م': 'meem',
    'د': 'dal',
    'س': 'seen',
  };

  List<HuntWord> huntWords = const []; // arabic_cache.json (65)
  List<LessonWord> lessonWords = const []; // lesson_words.json (145)
  List<PageWord> pageWords = const []; // page_words.json
  List<ArabicColour> colours = const []; // colours.json (11)
  List<Adjective> adjectives = const []; // adjectives.json (26)
  List<Json> sentenceTemplates = const []; // sentence_templates.json (raw)
  List<BankEntry> sentenceBank = const []; // sentence_bank.json (optional until copied in)
  Map<String, LetterInfo> letters = const {}; // letter_positions.json
  Map<String, Json> lessons = const {}; // per-letter lesson JSON (optional until made)
  Map<String, Json> jujuLines = const {}; // juju_lines.json: Juju's short lines per screen

  Map<String, HuntWord> _huntById = const {};
  Map<String, ArabicColour> _colourById = const {};
  Map<String, Adjective> _adjById = const {};
  Map<String, BankEntry> _bankById = const {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  /// Safe to call many times; only loads once. Retries after a failure.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() {
      if (!_loaded) _loading = null;
    });
  }

  Future<void> _load() async {
    // Start all reads together, then collect.
    final hunt = _list('arabic_cache.json');
    final lesson = _list('lesson_words.json');
    final page = _list('page_words.json');
    final col = _list('colours.json');
    final adj = _list('adjectives.json');
    final tmpl = _list('sentence_templates.json');
    final pos = _map('letter_positions.json');
    final bank = _optional('sentence_bank.json');
    final juju = _optional('juju_lines.json');
    final lessonFutures = {
      for (final e in lessonFiles.entries) e.key: _optional('lessons/${e.value}.json'),
    };

    huntWords = (await hunt).map(HuntWord.fromJson).toList();
    lessonWords = (await lesson).map(LessonWord.fromJson).toList();
    pageWords = (await page).map(PageWord.fromJson).toList();
    colours = (await col).map(ArabicColour.fromJson).toList();
    adjectives = (await adj).map(Adjective.fromJson).toList();
    sentenceTemplates = await tmpl;
    letters = {
      for (final e in (await pos).entries)
        e.key: LetterInfo(e.key, Json.from(e.value as Map)),
    };
    sentenceBank = _asList(await bank).map(BankEntry.fromJson).toList();

    final loadedLessons = <String, Json>{};
    for (final e in lessonFutures.entries) {
      final data = await e.value;
      if (data is Map) loadedLessons[e.key] = Json.from(data);
    }
    lessons = loadedLessons;

    final j = await juju;
    jujuLines = j is Map
        ? {for (final e in j.entries) e.key.toString(): Json.from(e.value as Map)}
        : const {};

    _huntById = {for (final w in huntWords) w.id: w};
    _colourById = {for (final c in colours) c.id: c};
    _adjById = {for (final a in adjectives) a.id: a};
    _bankById = {for (final b in sentenceBank) b.id: b};
    _loaded = true;

    debugPrint('Repository: ${huntWords.length} hunt words, '
        '${lessonWords.length} lesson words, ${sentenceBank.length} bank words, '
        'lessons: ${lessons.keys.join(' ')}');
  }

  // ---------- lookups ----------
  HuntWord? huntWord(String id) => _huntById[id];
  ArabicColour? colour(String id) => _colourById[id];
  Adjective? adjective(String id) => _adjById[id];
  BankEntry? bankEntry(String wordId) => _bankById[wordId];
  LetterInfo? letterInfo(String letter) => letters[letter];
  Json? lesson(String letter) => lessons[letter];
  Json? jujuLine(String id) => jujuLines[id];
  bool isOpenLetter(String letter) => hackathonLetters.contains(letter);

  List<LessonWord> lessonWordsFor(String letter) =>
      lessonWords.where((w) => w.letter == letter).toList();

  List<HuntWord> huntWordsForLetter(String letter) =>
      huntWords.where((w) => baseLetter(w.letter) == baseLetter(letter)).toList();

  /// أ إ آ ٱ count as ا (the lesson letter for أَرِيكَة is ا).
  static String baseLetter(String s) => 'أإآٱ'.contains(s) && s.isNotEmpty ? 'ا' : s;

  // ---------- file helpers ----------
  static const _dir = 'assets/data/';

  Future<dynamic> _read(String file) async =>
      jsonDecode(await rootBundle.loadString('$_dir$file'));

  Future<List<Json>> _list(String file) async => _asList(await _read(file));

  Future<Json> _map(String file) async => Json.from(await _read(file) as Map);

  /// Missing optional files return null instead of stopping the app.
  Future<dynamic> _optional(String file) async {
    try {
      return await _read(file);
    } catch (_) {
      debugPrint('Repository: optional $file not found (ok for now)');
      return null;
    }
  }

  static List<Json> _asList(dynamic data) =>
      data is List ? data.map((e) => Json.from(e as Map)).toList() : const [];
}
