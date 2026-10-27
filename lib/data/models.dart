// Typed models for the JSON in assets/data/.
// Every model keeps its original map in `raw`, so new JSON fields are never lost.

typedef Json = Map<String, dynamic>;

String _s(Json j, String k, [String fallback = '']) =>
    (j[k] as String?) ?? fallback;
List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

/// A skill tile's state on the My Letter hub. Never a "wrong" state.
enum SkillState { done, next, todo }

/// Hunt word – one entry of arabic_cache.json (65 home objects).
class HuntWord {
  HuntWord(this.raw);
  factory HuntWord.fromJson(Json j) => HuntWord(j);
  final Json raw;

  String get id => _s(raw, 'id');
  String get englishWord => _s(raw, 'english_word');
  String get arabicWord => _s(raw, 'arabic_word'); // indefinite, no case ending
  String get definite => _s(raw, 'definite');
  String get phonetic => _s(raw, 'phonetic');
  String get definitePhonetic => _s(raw, 'definite_phonetic');
  String get letter => _s(raw, 'letter');
  String get gender => _s(raw, 'gender', 'M'); // 'M' or 'F'
  bool get isFeminine => gender == 'F';
  String get category => _s(raw, 'category');
  String? get action => raw['action'] as String?;
  String get hint => _s(raw, 'hint');
  String get hintAudio => _s(raw, 'hint_audio');
  String get room => _s(raw, 'room');
  List<String> get adjectives => _strings(raw['adjectives']);
  bool get sizeChoice => (raw['size_choice'] as bool?) ?? true;
  String? get form => raw['form'] as String?; // 'indeclinable' | 'maqsur'
  String? get idafaTail => raw['idafa_tail'] as String?;
  String get headPh => _s(raw, 'head_ph');
  String get tailPh => _s(raw, 'tail_ph');
  String get enIndef => _s(raw, 'en_indef');
  String get enDef => _s(raw, 'en_def');
  bool get enPlural => raw['en_plural'] == true;
  String? get schoolWord => raw['school_word'] as String?;
  String get sticker => 'assets/images/$id.webp';
}

/// Lesson word – lesson_words.json (5–6 per letter).
class LessonWord {
  LessonWord(this.raw);
  factory LessonWord.fromJson(Json j) => LessonWord(j);
  final Json raw;

  String get id => _s(raw, 'id');
  String get letter => _s(raw, 'letter');
  String get type => _s(raw, 'type'); // 'Hunt' | 'Lesson'
  String get arabic => _s(raw, 'arabic');
  String get english => _s(raw, 'english');
  String get phonetic => _s(raw, 'phonetic');
  String get gender => _s(raw, 'gender', 'M');
  bool get isFeminine => gender == 'F';
  bool get needsCheck => raw['needs_check'] == true;
  String get sticker => _s(raw, 'sticker');
}

/// Extra picture words used in the lesson pages – page_words.json.
class PageWord {
  PageWord(this.raw);
  factory PageWord.fromJson(Json j) => PageWord(j);
  final Json raw;

  String get id => _s(raw, 'id');
  String get arabic => _s(raw, 'arabic');
  String get english => _s(raw, 'english');
  List<String> get letters => _strings(raw['letters']);
  String get sticker => _s(raw, 'sticker');
}

/// Shared shape of colours.json and adjectives.json: masculine + feminine forms.
abstract class GenderedWord {
  Json get raw;
  String get id => _s(raw, 'id');
  String get en => _s(raw, 'en');
  String get m => _s(raw, 'm');
  String get f => _s(raw, 'f');
  String get phM => _s(raw, 'ph_m');
  String get phF => _s(raw, 'ph_f');
  String? get visualCue => raw['visual_cue'] as String?;

  /// (arabic, phonetic) for a noun of this gender.
  (String, String) forGender(String gender) =>
      gender == 'F' ? (f, phF) : (m, phM);
}

class ArabicColour extends GenderedWord {
  ArabicColour(this.raw);
  factory ArabicColour.fromJson(Json j) => ArabicColour(j);
  @override
  final Json raw;
  bool get diptote =>
      raw['diptote'] == true; // أَحْمَرُ / حَمْرَاءُ: no tanween
}

class Adjective extends GenderedWord {
  Adjective(this.raw);
  factory Adjective.fromJson(Json j) => Adjective(j);
  @override
  final Json raw;
  String get group => _s(raw, 'group');
}

/// Letter shapes – letter_positions.json.
class LetterInfo {
  LetterInfo(this.letter, this.raw);
  final String letter;
  final Json raw;

  String get name => _s(raw, 'name');
  bool get connects => raw['connects'] == true; // joins to the next letter?

  /// 'beginning' | 'middle' | 'end' → entries like "بَاب (Door)".
  List<String> wordsAt(String position) {
    final p = raw['positions'];
    return p is Map ? _strings(p[position]) : const [];
  }
}

/// One sentence to show and say. Used by the sentence bank and by stories.
class SentenceLine {
  SentenceLine(this.raw);
  factory SentenceLine.fromJson(Json j) => SentenceLine(j);
  final Json raw;

  String get arabic => _s(raw, 'arabic'); // display: full marks, never stripped
  String get audioText => _s(raw, 'audio_text'); // for live TTS only
  String get phonetic => _s(raw, 'phonetic');
  String get english => _s(raw, 'english');
  String? get audio => raw['audio'] as String?; // pre-made file name, if any
  String? get template => raw['template'] as String?;
  List<String> get highlight => _strings(raw['highlight']); // words to colour
  String? get imagePrompt => raw['image_prompt'] as String?; // story pages

  Json toJson() => raw;
}

/// One word in sentence_bank.json with its 5 core sentences.
class BankEntry {
  BankEntry(this.raw);
  factory BankEntry.fromJson(Json j) => BankEntry(j);
  final Json raw;

  String get id => _s(raw, 'id');
  String get wordAudio => _s(raw, 'word_audio');
  String get sticker => _s(raw, 'sticker');
  List<SentenceLine> get sentences => raw['sentences'] is List
      ? (raw['sentences'] as List)
          .map((e) => SentenceLine(Json.from(e as Map)))
          .toList()
      : const [];
}

/// A child's personal story (Screen 11).
class Story {
  Story({
    required this.wordId,
    required this.lines,
    this.colour,
    this.size,
    this.fun,
  });

  final String wordId;
  final String? colour; // colour id
  final String? size; // 'big' | 'small'
  final String? fun; // 'happy' | 'funny'
  final List<SentenceLine> lines;

  Json toJson() => {
        'word_id': wordId,
        'colour': colour,
        'size': size,
        'fun': fun,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory Story.fromJson(Json j) => Story(
        wordId: _s(j, 'word_id'),
        colour: j['colour'] as String?,
        size: j['size'] as String?,
        fun: j['fun'] as String?,
        lines: (j['lines'] as List? ?? const [])
            .map((e) => SentenceLine(Json.from(e as Map)))
            .toList(),
      );
}
