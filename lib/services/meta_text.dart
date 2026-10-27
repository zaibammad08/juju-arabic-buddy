import 'dart:typed_data';

import '../data/arabic_forms.dart';
import '../data/models.dart';
import 'meta_client.dart';

class HandwritingResult {
  const HandwritingResult({required this.looksRight, required this.message});

  /// true = celebrate · false = gentle "try once more" · null = couldn't check
  /// (offline) → celebrate anyway. Never shown as wrong.
  final bool? looksRight;

  /// One short, kind English sentence for the parent / Juju's English voice.
  final String message;
}

/// Muse Spark text jobs. Every method has a safe fallback.
class MetaText {
  MetaText._();
  static final MetaText instance = MetaText._();

  // ---------- Hint 2 (Treasure Hunt) ----------
  Future<String> hint2(HuntWord word) async {
    final fallback = "Let's look in the ${word.room}!";
    final reply = await MetaClient.instance.chat(
      system: 'You are a friendly camel helping a 5-year-old find an object at home.',
      user: 'Object: ${word.englishWord}. Where it usually is: ${word.room}. '
          'The child already heard this hint: "${word.hint}".\n'
          'Write ONE new hint in simple English, max 15 words.\n'
          "Rules: never say the object's name or the letters in it. Mention where to look. "
          'Be cheerful and encouraging. Never suggest climbing, touching anything hot or sharp, '
          'or going outside.\nReply with only the hint.',
      maxTokens: 60,
      temperature: 0.7,
    );
    if (reply == null) return fallback;
    final hint = reply.replaceAll('"', '').trim();
    final words = hint.split(RegExp(r'\s+'));
    final name = word.englishWord.toLowerCase();
    final leaks = hint.toLowerCase().contains(name) ||
        name.split(RegExp(r'[\s-]+')).any((p) => p.length > 2 && hint.toLowerCase().contains(p));
    if (hint.isEmpty || words.length > 20 || leaks) return fallback;
    return hint;
  }

  // ---------- Writing check (Write skill) ----------
  /// [png] = the child's drawing (canvas export). [target] = letter or word with marks.
  Future<HandwritingResult> checkHandwriting(Uint8List png, String target) async {
    const offline = HandwritingResult(looksRight: null, message: 'Lovely writing!');
    final reply = await MetaClient.instance.chat(
      system: 'You kindly check handwriting by children aged 5-7 learning Arabic. '
          'You only reply with JSON.',
      user: 'The child tried to write: ${ArabicForms.strip(target)}\n'
          'Be generous: wobbly lines, size and small slips are fine. '
          'Say looks_right=true if a teacher would recognise it. '
          'message: ONE short, warm sentence in simple English for the child '
          '(praise first; if not right, one tiny tip like "add the dot below"). '
          'Never say wrong, bad or mistake.\n'
          'Reply: {"looks_right": true, "message": "..."}',
      image: png,
      imageMime: 'image/png',
      json: true,
      temperature: 0.2,
      maxTokens: 80,
    );
    final data = MetaClient.parseJson(reply);
    if (data == null) return offline;
    final msg = (data['message'] ?? '').toString().trim();
    return HandwritingResult(
      looksRight: data['looks_right'] == true,
      message: msg.isEmpty || msg.length > 140 ? 'Great writing!' : msg,
    );
  }

  // ---------- Parent weekly report ----------
  /// [summary] = plain facts from ProgressService (letters, skills, words found).
  Future<String> parentReport(String summary) async {
    final reply = await MetaClient.instance.chat(
      system: "You write a short, warm weekly note to a parent about their child's "
          'Arabic practice at home. Plain English, 3-4 sentences, no headings. '
          'Only use the facts given. End with one simple idea for this week.',
      user: summary,
      maxTokens: 220,
    );
    return reply ?? summary;
  }

  // ---------- Ask Juju (parents) ----------
  /// Lesson questions only, 2–3 sentences. [lessonContext] = this week's letter,
  /// its words and sentences (from the lesson JSON), so answers stay on-topic.
  Future<String> askJuju(String question, {required String lessonContext}) async {
    const fallback =
        "Juju can't answer right now. Try again in a moment, or check the parent tip on the lesson screen.";
    final reply = await MetaClient.instance.chat(
      system: "You are Juju, a helper for parents of children learning school Arabic (MSA) "
          'at home in the UAE. Answer ONLY questions about this lesson, in 2-3 short '
          'sentences of simple English. Arabic words must have full vowel marks. '
          "If the question is not about the lesson, say kindly that you can only help "
          "with this week's lesson. Never give medical, legal or personal advice.\n\n"
          'Lesson:\n$lessonContext',
      user: question,
      maxTokens: 180,
    );
    return reply ?? fallback;
  }

  // ---------- Story page check ----------
  /// Does the picture match the sentence? null = couldn't check (show it anyway).
  Future<bool?> pictureMatches(Uint8List image, String englishSentence) async {
    final reply = await MetaClient.instance.chat(
      system: 'You check pictures for a children\'s story app. Reply with JSON only.',
      user: 'Sentence: "$englishSentence". Does the picture show this, with no text, '
          'no people and nothing scary? Reply {"ok": true} or {"ok": false}.',
      image: image,
      imageMime: 'image/png',
      json: true,
      temperature: 0,
      maxTokens: 20,
    );
    final data = MetaClient.parseJson(reply);
    return data == null ? null : data['ok'] == true;
  }
}
