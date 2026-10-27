import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import 'meta_client.dart';

/// One story picture. [file] null = keep showing the previous picture.
class StoryPicture {
  const StoryPicture(this.index, this.file);
  final int index;
  final File? file;
}

/// Muse Image edits for story pages, cached on the device by
/// word + choices + page, so the same story never costs twice.
class MetaImage {
  MetaImage._();
  static final MetaImage instance = MetaImage._();

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/story_cache');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  String _key(String s) => md5.convert(utf8.encode(s)).toString();

  /// Edit [source] with [prompt]. Cached by [cacheKey]. Returns null on failure.
  Future<File?> edit(Uint8List source, String prompt, {required String cacheKey}) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${_key(cacheKey)}.png');
    if (file.existsSync()) return file;
    final bytes = await MetaClient.instance.editImage(source, prompt);
    if (bytes == null) return null;
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// The picture chain for a story: page 1 edits the word's sticker, each next
  /// page edits the previous page, so changes add up. Lines without an
  /// image_prompt keep the previous picture. A failed page also keeps the
  /// previous picture (fallback), and the chain continues from it.
  Stream<StoryPicture> storyPictures(HuntWord word, Story story) async* {
    Uint8List? current;
    try {
      current = (await rootBundle.load(word.sticker)).buffer.asUint8List();
    } catch (e) {
      debugPrint('MetaImage: no sticker for ${word.id}: $e');
      for (var i = 0; i < story.lines.length; i++) {
        yield StoryPicture(i, null);
      }
      return;
    }

    // Each page's key includes every choice so far, so cached chains stay consistent.
    var chain = word.id;
    for (var i = 0; i < story.lines.length; i++) {
      final prompt = story.lines[i].imagePrompt;
      if (prompt == null) {
        yield StoryPicture(i, null);
        continue;
      }
      chain = '$chain|$prompt';
      final file = await edit(current!, prompt, cacheKey: chain);
      if (file != null) current = await file.readAsBytes();
      yield StoryPicture(i, file);
    }
  }

  /// Delete all cached story pictures (parents' settings).
  Future<void> clearCache() async {
    final dir = await _cacheDir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _dir = null;
  }
}
