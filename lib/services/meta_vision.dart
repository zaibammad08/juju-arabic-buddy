import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/arabic_forms.dart';
import '../data/repository.dart';
import 'meta_client.dart';

enum VisionStatus { ok, blurry, tooDark, nothingFound, offline }

class VisionObject {
  const VisionObject(
      {required this.id, required this.name, required this.confidence});
  final String id; // a hunt word id, or 'new'
  final String name; // simple English name
  final String confidence; // 'high' | 'medium' | 'low'

  bool get isKnown => id != 'new';
  bool get isLow => confidence == 'low';
}

class VisionResult {
  const VisionResult(this.status, {this.objects = const [], this.colour});
  final VisionStatus status;
  final List<VisionObject> objects; // most prominent first, max 3
  final String? colour; // a colours.json id, or null if unclear

  /// The object to use for this week's letter, else the first one.
  VisionObject? pick({String? letter}) {
    if (objects.isEmpty) return null;
    if (letter != null) {
      for (final o in objects) {
        final w = Repository.instance.huntWord(o.id);
        if (w != null &&
            Repository.baseLetter(w.letter) == Repository.baseLetter(letter)) {
          return o;
        }
      }
    }
    return objects.first;
  }
}

/// Muse Spark vision: photo → objects + colour.
/// The photo is only sent, never stored – the caller deletes its file after this.
class MetaVision {
  MetaVision._();
  static final MetaVision instance = MetaVision._();

  /// Room for Muse Spark's reasoning + the JSON answer.
  /// If the log shows "finish_reason: length", raise this.
  static int maxTokens = 6000;

  static const _system =
      'You are the vision component of a children\'s Arabic learning app. '
      'You only reply with JSON.';

  String _prompt() {
    final repo = Repository.instance;
    final ids = repo.huntWords
        .map((w) => '${w.id} (${w.englishWord.toLowerCase()})')
        .join(', ');
    final colours = repo.colours.map((c) => c.id).join(', ');
    return '''
Look at the photo and identify the main objects.
Allowed objects (use these exact ids): $ids
Rules:
- Return at most 3 objects, most prominent first.
- Use an id from the list when the object matches. If a clear, child-friendly everyday object is NOT on the list, return it with "id": "new" and a simple English name.
- Toys count as their toy id (a toy car is "toy_car").
- Do not identify people or describe them. Objects a person is holding still count.
- Also return the main object's colour: one of $colours, or "unclear".
- If too blurry: status "blurry". If too dark: "too_dark". If nothing suitable: "nothing_found" with an empty list.
- Answer quickly. Respond with JSON only:
{"status":"ok","objects":[{"id":"door","name":"door","confidence":"high"}],"colour":"brown"}''';
  }

  /// [jpeg] should be about 768 px on the long side (camera preset "medium").
  Future<VisionResult> identify(Uint8List jpeg) async {
    final reply = await MetaClient.instance.chat(
      system: _system,
      user: _prompt(),
      image: jpeg,
      json: true,
      temperature: 0,
      maxTokens: maxTokens,
      reasoningEffort: 'low',
    );
    final data = MetaClient.parseJson(reply);
    if (data == null) {
      debugPrint(
          'Meta vision: no JSON. Reply was: ${reply ?? "null (see Meta chat line above)"}');
      return const VisionResult(VisionStatus.offline);
    }
    debugPrint('Meta vision: $data');

    final status = switch (data['status']) {
      'blurry' => VisionStatus.blurry,
      'too_dark' => VisionStatus.tooDark,
      'nothing_found' => VisionStatus.nothingFound,
      _ => VisionStatus.ok,
    };

    final repo = Repository.instance;
    final objects = <VisionObject>[];
    for (final o in (data['objects'] as List? ?? const [])) {
      if (o is! Map) continue;
      var id = (o['id'] ?? 'new').toString();
      if (id != 'new' && repo.huntWord(id) == null)
        id = 'new'; // unknown id → new word
      objects.add(VisionObject(
        id: id,
        name: (o['name'] ?? '').toString(),
        confidence: (o['confidence'] ?? 'medium').toString(),
      ));
      if (objects.length == 3) break;
    }

    final c = data['colour']?.toString();
    final colour = c != null && repo.colour(c) != null ? c : null;

    if (status == VisionStatus.ok && objects.isEmpty) {
      return VisionResult(VisionStatus.nothingFound, colour: colour);
    }
    return VisionResult(status, objects: objects, colour: colour);
  }

  /// The child SAID a colour (transcript from MetaVoice). Local match first
  /// (English or Arabic, either gender) – no API call needed most of the time.
  Future<String?> colourFromSpeech(String transcript) async {
    final repo = Repository.instance;
    final heard = ArabicForms.normalise(transcript);
    for (final c in repo.colours) {
      final forms = [c.en, c.id, c.m, c.f].map(ArabicForms.normalise);
      if (forms.any((f) => f.isNotEmpty && heard.contains(f))) return c.id;
    }
    // Fallback: ask Muse Spark (reasoning needs room even for a one-word answer).
    final reply = await MetaClient.instance.chat(
      system:
          'You map a child\'s spoken words to one colour id. Reply with the id only.',
      user: 'Colour ids: ${repo.colours.map((c) => c.id).join(', ')}.\n'
          'The child said: "$transcript". Which colour id? If none, reply "none".',
      maxTokens: 2000,
      temperature: 0,
      reasoningEffort: 'low',
    );
    final id = reply?.toLowerCase().replaceAll(RegExp(r'[^a-z_]'), '');
    return id != null && repo.colour(id) != null ? id : null;
  }
}
