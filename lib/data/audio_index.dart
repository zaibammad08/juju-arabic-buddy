// Finds the ready-made mp3 for a letter or a word (assets/data/audio_index.json).
// Falls back to live TTS when a file is missing. Paths are relative to assets/audio/.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'repository.dart';
import '../services/audio.dart';

class AudioIndex {
  AudioIndex._();
  static final instance = AudioIndex._();

  Map<String, Map<String, String>> _letters = {};
  Map<String, String> _words = {};
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final j = jsonDecode(
          await rootBundle.loadString('assets/data/audio_index.json')) as Map;
      _letters = {
        for (final e in (j['letters'] as Map).entries)
          '${e.key}': {
            for (final f in (e.value as Map).entries) '${f.key}': '${f.value}'
          }
      };
      _words = {
        for (final e in (j['words'] as Map).entries) '${e.key}': '${e.value}'
      };
    } catch (_) {
      // no index: everything falls back to TTS
    }
  }

  /// kind: name | fatha | kasra | damma | long_a | long_i | long_u
  String? letterFile(String letter, [String kind = 'name']) =>
      _letters[Repository.baseLetter(letter)]?[kind];

  /// 'assets/images/page_cow.webp' → 'words/page_cow_word.mp3'
  String? wordFile(String? sticker) {
    if (sticker == null) return null;
    final id = sticker.split('/').last.split('.').first;
    return _words[id];
  }

  /// Letter name; withSound also plays its fatha sound (e.g. تَ) if there is one.
  Future<void> playLetter(String letter, {bool withSound = false}) async {
    await _ensureLoaded();
    final audio = AudioService.instance;
    final name = letterFile(letter);
    if (name != null) {
      await audio.playAsset(name, wait: true);
    } else {
      await audio.say(letter, voice: TtsVoice.lessonWord);
    }
    final sound = withSound ? letterFile(letter, 'fatha') : null;
    if (sound != null) {
      await Future.delayed(const Duration(milliseconds: 250));
      await audio.playAsset(sound, wait: true);
    }
  }

  /// A word: its mp3 (found by sticker id) or live TTS of [text].
  Future<void> playWord(String text, {String? sticker}) async {
    await _ensureLoaded();
    final f = wordFile(sticker);
    if (f != null) {
      await AudioService.instance.playAsset(f, wait: true);
    } else {
      await AudioService.instance.say(text, voice: TtsVoice.lessonWord);
    }
  }
}
