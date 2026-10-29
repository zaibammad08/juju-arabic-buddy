import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'config.dart';

/// Thin HTTP layer for the Meta Model API (OpenAI-style endpoints).
/// Only the files in services/ use this. Every method returns null on any
/// problem (no key, offline, timeout, bad reply) – callers use their fallback.
class MetaClient {
  MetaClient._();
  static final MetaClient instance = MetaClient._();

  final _http = http.Client();

  Map<String, String> get _auth =>
      {'Authorization': 'Bearer ${AppConfig.metaApiKey}'};
  Uri _u(String path) => Uri.parse('${AppConfig.metaBaseUrl}$path');

  /// Chat completion. [image] adds one picture to the user message.
  /// [json] asks for a JSON object reply. On a 400 it retries once without
  /// JSON mode, temperature and reasoning_effort (some reasoning models reject them).
  Future<String?> chat({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 300,
    double temperature = 0.4,
    String? reasoningEffort, // 'low' | 'medium' | 'high' – null = model decides
  }) async {
    if (!AppConfig.hasMeta) {
      debugPrint(
          'Meta: NO KEY – run with --dart-define-from-file=secrets.json');
      return null;
    }

    final userContent = image == null
        ? user
        : [
            {'type': 'text', 'text': user},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$imageMime;base64,${base64Encode(image)}'
              },
            },
          ];

    Map<String, dynamic> body({bool simple = false}) => {
          'model': AppConfig.sparkModel,
          'max_tokens': maxTokens,
          if (!simple) 'temperature': temperature,
          if (!simple && reasoningEffort != null)
            'reasoning_effort': reasoningEffort,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': userContent},
          ],
          if (json && !simple) 'response_format': {'type': 'json_object'},
        };

    try {
      var res = await _post('/chat/completions', body());
      if (res.statusCode == 400) {
        debugPrint(
            'Meta chat 400, retrying without json/temperature/reasoning: ${_short(res.body)}');
        res = await _post('/chat/completions', body(simple: true));
      }
      if (res.statusCode != 200) {
        debugPrint('Meta chat ${res.statusCode}: ${_short(res.body)}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final choice = data['choices']?[0];
      final content = choice?['message']?['content'];
      String? text;
      if (content is String) text = content.trim();
      if (content is List) {
        text =
            content.map((p) => p is Map ? (p['text'] ?? '') : '').join().trim();
      }
      if (text == null || text.isEmpty) {
        debugPrint(
            'Meta chat: empty reply (finish_reason: ${choice?['finish_reason']})');
        return null;
      }
      return text;
    } catch (e) {
      debugPrint('Meta chat failed: $e');
      return null;
    }
  }

  /// Speech to text with Muse Voice Transcribe (recorded clip).
  ///
  /// POST /v1/asr/transcribe, multipart with two parts:
  ///   `request` – JSON {model, audioEncoding: "WAV", mode, languageBias, keywords}
  ///   `audio`   – a WAV file: mono, 16-bit PCM, 16 kHz or 24 kHz.
  /// Reply: {sessionId, transcript, audioDurationMs, turns[]} → returns `transcript`.
  ///
  /// [languageBias] takes language NAMES ("Arabic"), not codes ("ar").
  /// [keywords] biases recognition toward those words. Off by default: on very
  /// short clips it can make the model "hear" the keyword even when it wasn't said.
  Future<String?> transcribe(
    Uint8List wav, {
    String filename = 'speech.wav',
    List<String> languageBias = const ['Arabic'],
    List<String> keywords = const [],
    String mode = 'PUSH_TO_TALK',
  }) async {
    if (!AppConfig.hasMeta) return null;
    if (!_isWav(wav)) {
      debugPrint(
          'Meta transcribe: audio is not WAV – record with AudioEncoder.wav');
      return null;
    }
    try {
      final request = jsonEncode({
        'model': AppConfig.voiceModel,
        'audioEncoding': 'WAV',
        'mode': mode,
        if (languageBias.isNotEmpty) 'languageBias': languageBias,
        if (keywords.isNotEmpty) 'keywords': keywords,
      });
      final req = http.MultipartRequest('POST', _u('/asr/transcribe'))
        ..headers.addAll(_auth)
        ..files.add(http.MultipartFile.fromString('request', request,
            contentType: MediaType('application', 'json')))
        ..files.add(http.MultipartFile.fromBytes('audio', wav,
            filename: filename, contentType: MediaType('audio', 'wav')));
      final res = await http.Response.fromStream(
          await _http.send(req).timeout(AppConfig.timeout));
      if (res.statusCode != 200) {
        debugPrint('Meta transcribe ${res.statusCode}: ${_short(res.body)}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final text = (data['transcript'] as String?)?.trim();
      debugPrint(
          'Meta transcribe heard: "$text" (${data['audioDurationMs']} ms)');
      return text;
    } catch (e) {
      debugPrint('Meta transcribe failed: $e');
      return null;
    }
  }

  static bool _isWav(Uint8List b) =>
      b.length > 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 && // RIFF
      b[8] == 0x57 &&
      b[9] == 0x41 &&
      b[10] == 0x56 &&
      b[11] == 0x45; // WAVE

  /// Image edit: returns PNG/JPEG bytes, or null.
  Future<Uint8List?> editImage(Uint8List source, String prompt,
      {String filename = 'image.png'}) async {
    if (!AppConfig.hasMeta) return null;
    try {
      final req = http.MultipartRequest('POST', _u('/images/edits'))
        ..headers.addAll(_auth)
        ..fields['model'] = AppConfig.imageModel
        ..fields['prompt'] = prompt
        ..fields['n'] = '1'
        ..files.add(
            http.MultipartFile.fromBytes('image', source, filename: filename));
      final res = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 60)));
      return _imageFrom(res);
    } catch (e) {
      debugPrint('Meta image edit failed: $e');
      return null;
    }
  }

  /// Image generation (live "New word!" stickers).
  Future<Uint8List?> generateImage(String prompt) async {
    if (!AppConfig.hasMeta) return null;
    try {
      final res = await _post('/images/generations',
          {'model': AppConfig.imageModel, 'prompt': prompt, 'n': 1},
          timeout: const Duration(seconds: 60));
      return _imageFrom(res);
    } catch (e) {
      debugPrint('Meta image generate failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _imageFrom(http.Response res) async {
    if (res.statusCode != 200) {
      debugPrint('Meta image ${res.statusCode}: ${_short(res.body)}');
      return null;
    }
    final item = jsonDecode(utf8.decode(res.bodyBytes))['data']?[0];
    if (item is! Map) return null;
    if (item['b64_json'] is String)
      return base64Decode(item['b64_json'] as String);
    if (item['url'] is String) {
      final img = await _http
          .get(Uri.parse(item['url'] as String))
          .timeout(AppConfig.timeout);
      return img.statusCode == 200 ? img.bodyBytes : null;
    }
    return null;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body,
          {Duration timeout = AppConfig.timeout}) =>
      _http
          .post(_u(path),
              headers: {..._auth, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);

  static String _short(String s) =>
      s.length > 300 ? '${s.substring(0, 300)}…' : s;

  /// Pull the first {...} out of a reply (handles ```json fences and chatter).
  static Map<String, dynamic>? parseJson(String? reply) {
    if (reply == null) return null;
    final start = reply.indexOf('{'), end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(reply.substring(start, end + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
