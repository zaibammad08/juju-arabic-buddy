/// Keys and model ids come from a local secrets file, never from code or git:
///
///   flutter run --dart-define-from-file=secrets.json
///
/// secrets.json (in the project root, listed in .gitignore):
///   { "META_API_KEY": "...", "AZURE_TTS_KEY": "...", "AZURE_TTS_REGION": "uaenorth" }
///
/// Note: --dart-define values end up inside the built app. Fine for the hackathon
/// demo; for a public release, move these calls behind a small server.
class AppConfig {
  AppConfig._();

  static const metaApiKey = String.fromEnvironment('META_API_KEY');
  static const metaBaseUrl =
      String.fromEnvironment('META_BASE_URL', defaultValue: 'https://api.meta.ai/v1');

  // Model ids – confirm on dev.meta.ai and override in secrets.json if different.
  static const sparkModel =
      String.fromEnvironment('META_SPARK_MODEL', defaultValue: 'muse-spark-1.1');
  static const voiceModel = String.fromEnvironment('META_VOICE_MODEL',
      defaultValue: 'muse-voice-transcribe-1.0');
  static const imageModel =
      String.fromEnvironment('META_IMAGE_MODEL', defaultValue: 'muse-image-1.0');

  static const azureKey = String.fromEnvironment('AZURE_TTS_KEY');
  static const azureRegion =
      String.fromEnvironment('AZURE_TTS_REGION', defaultValue: 'uaenorth');

  static bool get hasMeta => metaApiKey.isNotEmpty;
  static bool get hasAzure => azureKey.isNotEmpty;

  static const timeout = Duration(seconds: 25);
}
