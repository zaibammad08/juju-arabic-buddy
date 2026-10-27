import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// Thin HTTP layer for the Meta Model API (OpenAI-style endpoints).
/// Only the files in services/ use this. Every method returns null on any
/// problem (no key, offline, timeout, bad reply) – callers use their fallback.
class MetaClient {
  MetaClient._();
  static final MetaClient instance = MetaClient._();

  final _http = http.Client();

  Map<String, String> get _auth => {'Authorization': 'Bearer ${AppConfig.metaApiKey}'};
  Uri _u(String path) => Uri.parse('${AppConfig.metaBaseUrl}$path');

  /// Chat completion. [image] adds one picture to the user message.
  /// [json] asks for a JSON object reply (retried without it if unsupported).
  Future<String?> chat({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 300,
    double temperature = 0.4,
  }) async {
    if (!AppConfig.hasMeta) return null;

    final userContent = image == null
        ? user
        : [
            {'type': 'text', 'text': user},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$imageMime;base64,${base64Encode(image)}'},
            },
          ];

    Map<String, dynamic> body(bool withJson) => {
          'model': AppConfig.sparkModel,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': userContent},
          ],
          if (withJson) 'response_format': {'type': 'json_object'},
        };

    try {
      var res = await _post('/chat/completions', body(json));
      if (json && res.statusCode == 400) {
        res = await _post('/chat/completions', body(false)); // JSON mode unsupported
      }
      if (res.statusCode != 200) {
        debugPrint('Meta chat ${res.statusCode}: ${_short(res.body)}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      if (content is String) return content.trim();
      if (content is List) {
        return content.map((p) => p is Map ? (p['text'] ?? '') : '').join().trim();
      }
      return null;
    } catch (e) {
      debugPrint('Meta chat failed: $e');
      return null;
    }
  }

  /// Speech to text. [prompt] = keyword hint (the target word).
  Future<String?> transcribe(Uint8List audio, {String filename = 'speech.m4a',
      String language = 'ar', String? prompt}) async {
    if (!AppConfig.hasMeta) return null;
    try {
      final req = http.MultipartRequest('POST', _u('/audio/transcriptions'))
        ..headers.addAll(_auth)
        ..fields['model'] = AppConfig.voiceModel
        ..fields['language'] = language
        ..files.add(http.MultipartFile.fromBytes('file', audio, filename: filename));
      if (prompt != null) req.fields['prompt'] = prompt;
      final res = await http.Response.fromStream(
          await _http.send(req).timeout(AppConfig.timeout));
      if (res.statusCode != 200) {
        debugPrint('Meta transcribe ${res.statusCode}: ${_short(res.body)}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return (data['text'] as String?)?.trim();
    } catch (e) {
      debugPrint('Meta transcribe failed: $e');
      return null;
    }
  }

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
        ..files.add(http.MultipartFile.fromBytes('image', source, filename: filename));
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
    if (item['b64_json'] is String) return base64Decode(item['b64_json'] as String);
    if (item['url'] is String) {
      final img = await _http.get(Uri.parse(item['url'] as String)).timeout(AppConfig.timeout);
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

  static String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;

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
