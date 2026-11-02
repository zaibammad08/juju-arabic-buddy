// Muse Spark checks for the Juju Magic World games.
// Same keys as the rest of the app (--dart-define-from-file=secrets.json).
// Never throws: every method returns null when it can't check (offline, no key,
// bad reply) and the screens then praise the child and move on.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FeedCheck {
  final String object; // what Muse Spark saw, simple English
  final List<bool> results; // one per rule, same order
  const FeedCheck(this.object, this.results);
  bool get allPass => results.isNotEmpty && results.every((r) => r);
}

class DetectiveCheck {
  final bool match;
  final String object;
  const DetectiveCheck(this.match, this.object);
}

class ShapeCheck {
  final bool looksRight;
  final Rect? box; // fractions of the image (0–1), null if not given
  const ShapeCheck(this.looksRight, this.box);
}

class DrawingGuess {
  final String thing; // one of the candidates, or ''
  final String colour; // one of the colour ids, or ''
  const DrawingGuess(this.thing, this.colour);
}

class MetaGames {
  MetaGames._();
  static final MetaGames instance = MetaGames._();

  static const _key = String.fromEnvironment('META_API_KEY');
  static const _base = String.fromEnvironment('META_BASE_URL',
      defaultValue: 'https://api.meta.ai/v1');
  static const _model = String.fromEnvironment('META_SPARK_MODEL',
      defaultValue: 'muse-spark-1.1');

  bool get available => _key.isNotEmpty;

  /// Feed Juju: does the main object pass each rule?
  Future<FeedCheck?> feedCheck(Uint8List jpeg, List<String> rules) async {
    final numbered = [
      for (var i = 0; i < rules.length; i++) '${i + 1}. ${rules[i]}'
    ].join('\n');
    final j = await _ask(
      'A child is playing a riddle game and photographed something to "feed" a cartoon camel.\n'
      'Look at the MAIN object in the photo. Name it in 1–3 simple English words.\n'
      'Then check each rule about that object:\n$numbered\n'
      'Reply exactly as {"object": "...", "results": [true, false, ...]} with one true/false per rule, in order. '
      'If no clear object is visible, reply {"object": "", "results": []}.',
      jpeg,
    );
    if (j == null) return null;
    final obj = (j['object'] ?? '').toString().trim();
    final raw = j['results'];
    if (obj.isEmpty || raw is! List || raw.length != rules.length) return null;
    return FeedCheck(obj, [for (final r in raw) r == true]);
  }

  /// Juju Detective: is the main object the target word?
  Future<DetectiveCheck?> detectiveCheck(
      Uint8List jpeg, String targetEnglish) async {
    final j = await _ask(
      'A child was asked to find a "$targetEnglish" at home and took this photo.\n'
      'Is the main object a $targetEnglish? A real one, a toy one or a clear picture of one all count.\n'
      'Reply exactly as {"match": true or false, "object": "what you see, 1–3 simple English words"}.',
      jpeg,
    );
    if (j == null || j['match'] is! bool) return null;
    return DetectiveCheck(
        j['match'] as bool, (j['object'] ?? '').toString().trim());
  }

  /// Playdough Magic: does the dough (or finger drawing) look like the target shape?
  /// Playdough Magic: does the dough (or finger drawing) look like the target shape?
  Future<ShapeCheck?> shapeCheck(Uint8List image, String shapeDescription,
      {bool isDrawing = false}) async {
    final what =
        isDrawing ? 'drew with a finger on a screen' : 'made out of playdough';
    final j = await _ask(
      'A 5-year-old $what a shape. The target is $shapeDescription '
      '(an open curve like a smile or a boat: wider than it is tall, open at the top, '
      'one end may be higher than the other).\n'
      'The photo may be rotated and may have a busy background (cloth, patterns, a book). '
      "Look only at the child's shape and judge it as if turned the right way up.\n"
      'Be very kind: thick, wobbly, shallow, lumpy, uneven or one-side-higher shapes count. '
      'Say false ONLY if it is clearly a different shape: a closed circle or ring, '
      'a straight line, a zigzag, a scribble, or no shape at all.\n'
      'Ignore dots completely; the target has no dots.\n'
      'Reply exactly as {"looks_right": true or false, "seen": "<what you see, max 4 words>", '
      '"box": [x, y, w, h]} where box is the bounding box of the child\'s shape as fractions '
      '(0 to 1) of the image width and height, in the image exactly as given.',
      image,
      mime: isDrawing ? 'image/png' : 'image/jpeg',
    );
    debugPrint('shapeCheck: $j');
    if (j == null || j['looks_right'] is! bool) return null;
    Rect? box;
    final b = j['box'];
    if (b is List && b.length == 4 && b.every((v) => v is num)) {
      final v = [for (final n in b) (n as num).clamp(0, 1).toDouble()];
      if (v[2] > 0.02 && v[3] > 0.02) {
        box = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
      }
    }
    return ShapeCheck(j['looks_right'] as bool, box);
  }

  /// Story Maker: which known thing did the child draw, and in which colour?
  Future<DrawingGuess?> drawingGuess(
      Uint8List png, List<String> candidates, List<String> colourIds) async {
    final j = await _ask(
      'A young child drew this picture on a tablet.\n'
      'Which ONE of these things is it most likely? ${candidates.join(', ')}\n'
      'And what is the main colour of the drawn thing? One of: ${colourIds.join(', ')}\n'
      'Reply exactly as {"thing": "<one word from the list, or empty if nothing fits>", '
      '"colour": "<one colour from the list>"}.',
      png,
      mime: 'image/png',
    );
    if (j == null) return null;
    final thing = (j['thing'] ?? '').toString().trim().toLowerCase();
    final colour = (j['colour'] ?? '').toString().trim().toLowerCase();
    return DrawingGuess(candidates.contains(thing) ? thing : '',
        colourIds.contains(colour) ? colour : '');
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _ask(String prompt, Uint8List image,
      {String mime = 'image/jpeg'}) async {
    if (!available) return null;
    try {
      final body = {
        'model': _model,
        'temperature': 0,
        'messages': [
          {
            'role': 'system',
            'content':
                "You check photos and drawings for a children's Arabic learning game. "
                    'Reply with JSON only, no other text.'
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mime;base64,${base64Encode(image)}'}
              },
            ],
          },
        ],
      };
      final res = await http
          .post(Uri.parse('$_base/chat/completions'),
              headers: {
                'Authorization': 'Bearer $_key',
                'Content-Type': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        debugPrint('MetaGames ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      final text = content is String
          ? content
          : content is List
              ? content
                  .map((p) => p is Map ? (p['text'] ?? '').toString() : '')
                  .join()
              : '';
      return _parse(text);
    } catch (e) {
      debugPrint('MetaGames error: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _parse(String s) {
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final v = jsonDecode(s.substring(a, b + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
