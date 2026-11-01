import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';

import '../data/arabic_forms.dart';
import '../data/lex.dart';
import 'word_audio.dart';

/// FINAL voices (BUILD_GUIDE.md). tools/make_line_audio.py uses the same
/// settings to make the files, so keep the two in step.
enum TtsVoice {
  lessonWord('ar-AE', 'ar-AE-FatimaNeural',
      rate: '-20%'), // single words, letters, colours
  lesson('ar-AE', 'ar-AE-FatimaNeural'), // sentences, stories (natural)
  juju('ar-AE', 'ar-AE-FatimaNeural',
      pitch: '+25%', rate: '-8%'), // Juju in Arabic
  jujuEnglish('en-US', 'en-US-AnaNeural', rate: '-5%'), // Juju in English
  parent('en-US', 'en-US-JennyNeural'); // calm adult English

  const TtsVoice(this.lang, this.name, {this.pitch, this.rate});
  final String lang;
  final String name;
  final String? pitch;
  final String? rate;

  bool get isArabic => lang.startsWith('ar');

  /// Stable id used in file names: 'jujuEnglish', 'lesson', …
  String get id => toString().split('.').last;
}

/// Plays ONLY pre-made files from assets/audio/ – no speech service is called
/// while the app runs (hackathon rule).
///
/// Every spoken line has a fixed file name: assets/audio/tts/<voice>_<hash>.mp3,
/// made by tools/make_line_audio.py. Arabic sentences without their own file
/// are read word by word from existing clips (WordAudio). Anything still
/// missing is shown as text only and logged once as
///   MISSING_AUDIO|<voice>|<text>      (a line that needs a file)
///   MISSING_FILE|<path>               (code points at an mp3 that isn't there)
/// in the debug console and in missing_audio.txt (app support folder).
/// Feed that log to make_line_audio.py --log to make the files.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioPlayer _player = AudioPlayer();

  /// True while something is playing (e.g. animate Juju's mouth).
  final ValueNotifier<bool> playing = ValueNotifier(false);

  // ---------- which files exist ----------
  Set<String>? _assets;
  Future<Set<String>>? _assetsLoading;

  Future<Set<String>> _assetSet() async {
    if (_assets != null) return _assets!;
    _assetsLoading ??= () async {
      try {
        final m = await AssetManifest.loadFromAssetBundle(rootBundle);
        return m.listAssets().toSet();
      } catch (e) {
        debugPrint('AssetManifest failed: $e');
        return <String>{};
      }
    }();
    return _assets = await _assetsLoading!;
  }

  /// [path] relative to assets/audio/, e.g. 'words/door_word.mp3'.
  Future<bool> hasAsset(String path) async =>
      (await _assetSet()).contains('assets/audio/$path');

  // ---------- playing ----------

  /// [path] is relative to assets/audio/, e.g. 'words/door_word.mp3'.
  Future<bool> playAsset(String path, {bool wait = false}) async {
    if (!await hasAsset(path)) {
      _logMissing('MISSING_FILE|$path');
      return false;
    }
    return _play(AssetSource('audio/$path'), wait);
  }

  /// Speak a line from its pre-made file. For Arabic pass the `audio_text`
  /// field (never `arabic`). Returns false if there is no audio for it.
  Future<bool> say(String text,
      {TtsVoice voice = TtsVoice.lesson, bool wait = false}) async {
    final clean = cleanText(text, voice);
    if (clean.isEmpty) return false;

    // Arabic: the word library first (approved, named by word).
    if (voice.isArabic) {
      final lex = await Lex.instance.fileFor(clean);
      if (lex != null && await hasAsset(lex)) {
        return _play(AssetSource('audio/$lex'), wait);
      }
    }

    final file = lineFile(text, voice);
    if (await hasAsset(file)) return _play(AssetSource('audio/$file'), wait);

    // Arabic sentence with no file of its own: try word by word.
    if (voice.isArabic && await WordAudio.instance.play(clean, wait: wait)) {
      return true;
    }
    _logMissing('MISSING_AUDIO|${voice.id}|$clean');
    return false;
  }

  /// Pre-made file if there is one, otherwise the line file for [text].
  Future<bool> playOrSay(
      {String? asset,
      required String text,
      TtsVoice voice = TtsVoice.lesson,
      bool wait = false}) async {
    // An approved word-library file beats an older per-screen file.
    if (voice.isArabic) {
      final lex = await Lex.instance.fileFor(cleanText(text, voice));
      if (lex != null && await hasAsset(lex)) {
        return _play(AssetSource('audio/$lex'), wait);
      }
    }
    if (asset != null && asset.isNotEmpty && await playAsset(asset, wait: wait)) {
      return true;
    }
    return say(text, voice: voice, wait: wait);
  }

  /// Play one entry of juju_lines.json: its file if present, else its line
  /// file in its voice ("juju", "jujuEnglish", "lesson", …).
  Future<bool> playLine(Map<String, dynamic>? line, {bool wait = false}) {
    if (line == null) return Future.value(false);
    final voice = TtsVoice.values.firstWhere(
      (v) => v.id == line['voice'],
      orElse: () => TtsVoice.juju,
    );
    final text = voice.isArabic
        ? (line['audio_text'] ?? line['arabic'] ?? '') as String
        : (line['english'] ?? '') as String;
    return playOrSay(
        asset: line['audio'] as String?, text: text, voice: voice, wait: wait);
  }

  Future<void> stop() async {
    _gen++; // also ends a word-by-word sentence
    try {
      await _player.stop();
    } catch (_) {}
    playing.value = false;
  }

  int _gen = 0; // which sound is the current one

  /// Changes whenever a new sound starts or stop() is called.
  int get generation => _gen;

  Future<bool> _play(Source source, bool wait) async {
    final gen = ++_gen;
    StreamSubscription<PlayerState>? sub;
    try {
      await _player.stop();

      // Done = this sound reached "completed" (or was stopped) AFTER it started.
      // Old events from an earlier sound are ignored.
      final done = Completer<void>();
      var started = false;
      sub = _player.onPlayerStateChanged.listen((s) {
        if (s == PlayerState.playing) {
          started = true;
        } else if (started &&
            (s == PlayerState.completed || s == PlayerState.stopped)) {
          if (!done.isCompleted) done.complete();
        }
      });

      playing.value = true;
      await _player.play(source);

      final finished = done.future
          .timeout(const Duration(seconds: 30), onTimeout: () {})
          .then((_) {
        if (gen == _gen) playing.value = false;
        sub?.cancel();
      });

      if (wait) await finished;
      return true;
    } catch (e) {
      debugPrint('Audio failed ($source): $e');
      await sub?.cancel();
      if (gen == _gen) playing.value = false;
      return false;
    }
  }

  // ---------- line file names (same rule in make_line_audio.py) ----------

  /// Text as it is spoken: Arabic without sukun, trimmed.
  static String cleanText(String text, TtsVoice voice) =>
      (voice.isArabic ? ArabicForms.forSpeech(text) : text).trim();

  /// 'tts/jujuEnglish_1a2b3c4d5e6f.mp3' = md5("<voice>|<clean text>"), 12 chars.
  static String lineFile(String text, TtsVoice voice) {
    final clean = cleanText(text, voice);
    final h = md5.convert(utf8.encode('${voice.id}|$clean')).toString();
    return 'tts/${voice.id}_${h.substring(0, 12)}.mp3';
  }

  // ---------- missing-audio log ----------
  final Set<String> _logged = {};
  File? _logFile;

  void _logMissing(String entry) {
    if (!_logged.add(entry)) return; // once per run
    debugPrint(entry);
    unawaited(_appendLog(entry));
  }

  Future<void> _appendLog(String entry) async {
    try {
      if (_logFile == null) {
        final base = await getApplicationSupportDirectory();
        _logFile = File('${base.path}/missing_audio.txt');
        debugPrint('Missing-audio log: ${_logFile!.path}');
      }
      await _logFile!.writeAsString('$entry\n', mode: FileMode.append);
    } catch (_) {}
  }
}
