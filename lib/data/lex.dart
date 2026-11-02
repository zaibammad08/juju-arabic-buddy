// lib/data/lex.dart
// The shared word library (assets/data/lex.json, made by tools/build_lex.py):
// one Arabic word or sentence -> one approved mp3 in assets/audio/lex/.
// Any screen that speaks Arabic finds its file here first, so a word fixed
// once (e.g. بِنْت) is right in every lesson.
//
// Lookup:
//   1. exact  - same rule as lex_key() in build_lex.py: every mark kept
//               except sukun, no punctuation, single spaces (أَ and إِ differ)
//   2. loose  - no marks at all (بنت still finds bint). Used only when that
//               loose spelling belongs to ONE library entry (أَ / أُ share
//               "أ", so they never match loosely).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class Lex {
  Lex._();
  static final Lex instance = Lex._();

  Map<String, String> _exact = const {};
  Map<String, String> _loose = const {};
  Future<void>? _loading;

  Future<void> _ensure() => _loading ??= _load();

  static final _punct = RegExp('[؟?!.،,:]');
  static final _spaces = RegExp(r'\s+');
  static final _allMarks =
      RegExp('[\u064B-\u0652\u0670\u0640\u200C\u200D\u200E\u200F]');

  /// Same as lex_key() in tools/build_lex.py – keep the two in step.
  static String exactKey(String text) => text
      .replaceAll('\u0652', '')
      .replaceAll(_punct, '')
      .replaceAll(_spaces, ' ')
      .trim();

  /// No marks at all.
  static String looseKey(String text) =>
      exactKey(text.replaceAll(_allMarks, ''));

  Future<void> _load() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/data/lex.json'))
          as Map<String, dynamic>;
      final exact = <String, String>{};
      final loose = <String, String>{};
      final clash = <String>{};
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map || v['file'] is! String) continue;
        final file = v['file'] as String;
        exact[exactKey(e.key)] = file;
        final l = looseKey(e.key);
        if (loose.containsKey(l) && loose[l] != file) {
          clash.add(l);
        } else {
          loose[l] = file;
        }
      }
      clash.forEach(loose.remove);
      _exact = exact;
      _loose = loose;
      debugPrint('Lex: ${exact.length} words loaded');
    } catch (e) {
      debugPrint('Lex: no library ($e)');
      _exact = const {};
      _loose = const {};
    }
  }

  /// 'lex/bint.mp3' for بِنْت (path relative to assets/audio/), or null.
  Future<String?> fileFor(String arabic) async {
    await _ensure();
    return _exact[exactKey(arabic)] ?? _loose[looseKey(arabic)];
  }
}
