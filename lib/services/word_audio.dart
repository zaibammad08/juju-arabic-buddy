// Reads an Arabic sentence word by word from clips that already exist:
//   small words   story/word_*.mp3          (هَذَا، هَذِهِ، عِنْدِي، أَنَا، أُحِبُّ، أَيْنَ)
//   hunt nouns    words/<id>_def.mp3        (الْبَاب – definite, if made)
//                 words/<id>_word.mp3       (بَاب)
//   colours       colours/colour_<id>_{m,f}.mp3
//   adjectives    adjectives/adj_<id>_{m,f}.mp3
// Used by AudioService.say() when a sentence has no file of its own, so any
// story or colour sentence still speaks without a live speech service.
// If ANY word has no clip, nothing plays (the caller logs the sentence).

import '../data/repository.dart';
import 'audio.dart';

class WordAudio {
  WordAudio._();
  static final WordAudio instance = WordAudio._();

  /// key → clip path ('' = part of the previous word, play nothing).
  Map<String, String>? _lex;

  static const _small = <String, String>{
    'هذا': 'story/word_hadha.mp3',
    'هذه': 'story/word_hadhihi.mp3',
    'عندي': 'story/word_indi.mp3',
    'انا': 'story/word_ana.mp3',
    'احب': 'story/word_uhibbu.mp3',
    'اين': 'story/word_ayna.mp3',
  };

  /// No tashkeel, no punctuation, hamza-alifs → ا. Keeps a leading ال.
  static String fullKey(String s) => s
      .replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp('[؟?!.،,:]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .trim();

  /// Same, without a leading ال (so الْبَابُ also matches بَاب).
  static String bareKey(String s) {
    final k = fullKey(s);
    return (k.startsWith('ال') && k.length > 3) ? k.substring(2) : k;
  }

  Map<String, String> _build() {
    final repo = Repository.instance;
    final lex = <String, String>{..._small};

    for (final w in repo.huntWords) {
      // definite form first (its own clip if it was made)
      final def = fullKey(w.definite);
      if (def.isNotEmpty)
        lex.putIfAbsent('=$def', () => 'words/${w.id}_def.mp3');
      // indefinite: the whole word is one clip; for two-word nouns
      // (فُرْشَاةُ أَسْنَانٍ) the second part plays nothing.
      final parts =
          w.arabicWord.split(' ').where((p) => p.trim().isNotEmpty).toList();
      for (var i = 0; i < parts.length; i++) {
        lex.putIfAbsent(
            bareKey(parts[i]), () => i == 0 ? 'words/${w.id}_word.mp3' : '');
      }
    }
    for (final c in repo.colours) {
      lex.putIfAbsent(bareKey(c.m), () => 'colours/colour_${c.id}_m.mp3');
      lex.putIfAbsent(bareKey(c.f), () => 'colours/colour_${c.id}_f.mp3');
    }
    for (final a in repo.adjectives) {
      lex.putIfAbsent(bareKey(a.m), () => 'adjectives/adj_${a.id}_m.mp3');
      lex.putIfAbsent(bareKey(a.f), () => 'adjectives/adj_${a.id}_f.mp3');
    }
    return lex;
  }

  /// Clip for every word of [sentence], or null if one is missing.
  Future<List<String>?> clipsFor(String sentence) async {
    final lex = _lex ??= _build();
    final audio = AudioService.instance;
    final out = <String>[];
    for (final word in sentence.split(RegExp(r'\s+'))) {
      if (fullKey(word).isEmpty) continue;
      final def = lex['=${fullKey(word)}'];
      if (def != null && await audio.hasAsset(def)) {
        out.add(def);
        continue;
      }
      final clip = lex[bareKey(word)];
      if (clip == null) return null;
      if (clip.isEmpty) continue; // second part of a two-word noun
      if (!await audio.hasAsset(clip)) return null;
      out.add(clip);
    }
    return out.isEmpty ? null : out;
  }

  /// Plays [sentence] word by word. False (and silent) if a clip is missing.
  Future<bool> play(String sentence, {bool wait = false}) async {
    final clips = await clipsFor(sentence);
    if (clips == null) return false;
    final run = _run(clips);
    if (wait) await run;
    return true;
  }

  Future<void> _run(List<String> clips) async {
    final audio = AudioService.instance;
    await audio.stop();
    var expected = audio.generation;
    for (var i = 0; i < clips.length; i++) {
      if (audio.generation != expected) return; // something else started
      await audio.playAsset(clips[i], wait: true);
      expected++; // our own clip moved the counter by one
      if (audio.generation != expected) return; // stopped or replaced
      if (i < clips.length - 1) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
  }
}
