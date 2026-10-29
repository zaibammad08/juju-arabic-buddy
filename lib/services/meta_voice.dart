import 'dart:typed_data';

import '../data/arabic_forms.dart';
import 'meta_client.dart';

class VoiceCheck {
  const VoiceCheck(
      {required this.heard, required this.matched, this.score = 0});

  /// What Muse Voice Transcribe heard (null = no reply).
  final String? heard;

  /// true = good match · false = try again (Juju takes the blame) ·
  /// null = couldn't check (offline / no key) → just praise and move on.
  final bool? matched;
  final double score;

  bool get couldCheck => matched != null;
}

/// Muse Voice Transcribe: did the child say the word?
/// Rule: strip marks, normalise letters, accept if similarity ≥ threshold
/// or the reply contains the target / an accepted variant.
class MetaVoice {
  MetaVoice._();
  static final MetaVoice instance = MetaVoice._();

  /// Tune on Day 1 with real recordings.
  static double threshold = 0.75;

  /// Send the target word as a keyword hint. Off: on short clips keywords can
  /// make the model "hear" the word even when the child said something else.
  /// Turn on only if real recordings show it mishears correct answers.
  static bool useKeywordHint = false;

  /// [audio] = WAV bytes (mono 16-bit PCM, 16 kHz) – record with
  /// `RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)`.
  /// Delete the file after this call.
  /// [target] = the word or sentence with marks (the `arabic` field is fine).
  Future<VoiceCheck> check(
    Uint8List audio, {
    required String target,
    List<String> variants = const [],
    String filename = 'speech.wav',
  }) async {
    final heard = await MetaClient.instance.transcribe(
      audio,
      filename: filename,
      languageBias: const ['Arabic'],
      keywords: useKeywordHint ? [ArabicForms.strip(target)] : const [],
    );
    if (heard == null) return const VoiceCheck(heard: null, matched: null);
    return compare(heard, target, variants: variants);
  }

  /// Pure comparison – easy to unit-test without the API.
  static VoiceCheck compare(String heard, String target,
      {List<String> variants = const []}) {
    final h = ArabicForms.normalise(heard);
    if (h.isEmpty) return VoiceCheck(heard: heard, matched: false);

    var best = 0.0;
    for (final t in [target, ...variants]) {
      final n = ArabicForms.normalise(t);
      if (n.isEmpty) continue;
      // Contains the word (child said "هذا باب" for "باب") – also without ال.
      if (h.contains(n) || (n.startsWith('ال') && h.contains(n.substring(2)))) {
        return VoiceCheck(heard: heard, matched: true, score: 1);
      }
      final s = ArabicForms.similarity(h, n);
      if (s > best) best = s;
    }
    return VoiceCheck(heard: heard, matched: best >= threshold, score: best);
  }
}
