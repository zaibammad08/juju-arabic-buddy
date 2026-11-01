// The shared word library (assets/data/lex.json, made by tools/build_lex.py):
// one Arabic word or sentence -> one approved mp3 in assets/audio/lex/.
// Any screen that speaks Arabic finds its file here first, so a word fixed
// once (e.g. بِنْت) is right in every lesson.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class Lex {
  Lex._();
  static final Lex instance = Lex._();

  Map<String, String> _files = const {};
  Future<void>? _loading;

  Future<void> _ensure() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/data/lex.json'))
          as Map<String, dynamic>;
      _files = {
        for (final e in j.entries)
          if (e.value is Map && (e.value as Map)['file'] is String)
            e.key: (e.value as Map)['file'] as String,
      };
    } catch (_) {
      _files = const {}; // no library yet: everything works as before
    }
  }

  /// Same rule as lex_key() in tools/build_lex.py: no marks, no punctuation,
  /// أ/إ/آ -> ا, single spaces.
  static String key(String text) => text
      .replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp('[؟?!.،,:]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 'lex/bint.mp3' for بِنْت (path relative to assets/audio/), or null.
  Future<String?> fileFor(String arabic) async {
    await _ensure();
    return _files[key(arabic)];
  }
}
