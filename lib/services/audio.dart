import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/arabic_forms.dart';
import 'config.dart';

/// FINAL voices (BUILD_GUIDE.md). Single words are slowed so they don't sound clipped.
enum TtsVoice {
  lessonWord('ar-AE', 'ar-AE-FatimaNeural', rate: '-20%'), // single words, letters, colours
  lesson('ar-AE', 'ar-AE-FatimaNeural'), // sentences, stories (natural)
  juju('ar-AE', 'ar-AE-FatimaNeural', pitch: '+25%', rate: '-8%'), // Juju in Arabic
  jujuEnglish('en-US', 'en-US-AnaNeural', rate: '-5%'), // Juju in English
  parent('en-US', 'en-US-JennyNeural'); // calm adult English – not final, change if you pick another

  const TtsVoice(this.lang, this.name, {this.pitch, this.rate});
  final String lang;
  final String name;
  final String? pitch;
  final String? rate;

  bool get isArabic => lang.startsWith('ar');
}

/// Plays the pre-made files in assets/audio/, and makes live speech
/// (stories, colour sentences) with Azure TTS – cached, so each line is paid once.
/// Every method returns false instead of throwing; screens then just show the text.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioPlayer _player = AudioPlayer();
  final _http = http.Client();
  Directory? _cache;

  /// True while something is playing (e.g. animate Juju's mouth).
  final ValueNotifier<bool> playing = ValueNotifier(false);

  /// [path] is relative to assets/audio/, e.g. 'words/door_word.mp3'.
  Future<bool> playAsset(String path, {bool wait = false}) =>
      _play(AssetSource('audio/$path'), wait);

  /// Speak live text. For Arabic pass the `audio_text` field (never `arabic`).
  Future<bool> say(String text, {TtsVoice voice = TtsVoice.lesson, bool wait = false}) async {
    final file = await ttsFile(text, voice);
    if (file == null) return false;
    return _play(DeviceFileSource(file.path), wait);
  }

  /// Pre-made file if there is one, otherwise live TTS.
  Future<bool> playOrSay({String? asset, required String text,
      TtsVoice voice = TtsVoice.lesson, bool wait = false}) async {
    if (asset != null && asset.isNotEmpty && await playAsset(asset, wait: wait)) return true;
    return say(text, voice: voice, wait: wait);
  }

  /// Play one entry of juju_lines.json: its file if present, else live TTS
  /// in its voice ("juju", "jujuEnglish", "lesson", …).
  Future<bool> playLine(Map<String, dynamic>? line, {bool wait = false}) {
    if (line == null) return Future.value(false);
    final voice = TtsVoice.values.firstWhere(
      (v) => v.name == line['voice'],
      orElse: () => TtsVoice.juju,
    );
    final text = voice.isArabic
        ? (line['audio_text'] ?? line['arabic'] ?? '') as String
        : (line['english'] ?? '') as String;
    return playOrSay(asset: line['audio'] as String?, text: text, voice: voice, wait: wait);
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    playing.value = false;
  }

  Future<bool> _play(Source source, bool wait) async {
    try {
      await _player.stop();
      final done = _player.onPlayerComplete.first;
      playing.value = true;
      await _player.play(source);
      if (wait) {
        await done.timeout(const Duration(seconds: 30), onTimeout: () {});
        playing.value = false;
      } else {
        unawaited(done.then((_) => playing.value = false, onError: (_) {}));
      }
      return true;
    } catch (e) {
      debugPrint('Audio failed ($source): $e');
      playing.value = false;
      return false;
    }
  }

  // ---------- Azure TTS + cache ----------
  Future<File?> ttsFile(String text, TtsVoice voice) async {
    final clean = voice.isArabic ? ArabicForms.forSpeech(text) : text;
    if (clean.trim().isEmpty) return null;

    final dir = await _cacheDir();
    final key = md5.convert(utf8.encode('${voice.name}|${voice.pitch}|${voice.rate}|$clean'));
    final file = File('${dir.path}/$key.mp3');
    if (file.existsSync() && file.lengthSync() > 0) return file;
    if (!AppConfig.hasAzure) return null;

    try {
      final res = await _http
          .post(
            Uri.parse('https://${AppConfig.azureRegion}.tts.speech.microsoft.com/cognitiveservices/v1'),
            headers: {
              'Ocp-Apim-Subscription-Key': AppConfig.azureKey,
              'Content-Type': 'application/ssml+xml',
              'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
              'User-Agent': 'ArabicBuddy',
            },
            body: utf8.encode(_ssml(clean, voice)),
          )
          .timeout(AppConfig.timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        debugPrint('Azure TTS ${res.statusCode}');
        return null;
      }
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('Azure TTS failed: $e');
      return null;
    }
  }

  static String _ssml(String text, TtsVoice v) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    final attrs = [
      if (v.pitch != null) 'pitch="${v.pitch}"',
      if (v.rate != null) 'rate="${v.rate}"',
    ].join(' ');
    final inner = attrs.isEmpty ? escaped : '<prosody $attrs>$escaped</prosody>';
    return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="${v.lang}"><voice name="${v.name}">$inner</voice></speak>';
  }

  Future<Directory> _cacheDir() async {
    if (_cache != null) return _cache!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/tts_cache');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _cache = d;
  }
}
