import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Only upload metadata is stored here, never credentials or signed URLs.
abstract interface class PendingPublicMediaStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<String> retainPreview(String id, String sourcePath);
  Future<void> prunePreviews(Set<String> retainedPaths);
  Future<void> clear();
}

class DevicePendingPublicMediaStore implements PendingPublicMediaStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'pending_public_media_v1';

  static const _previewsFolder = 'kmstry_upload_previews_v1';

  Future<Directory> _directory() async {
    final cache = await getApplicationCacheDirectory();
    return Directory(p.join(cache.path, _previewsFolder));
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final result = Map<String, dynamic>.from(value);
      await _rebasePreviewPaths(result);
      return result;
    } on FormatException {
      return null;
    }
  }

  /// iOS can move the app container (its absolute path contains a UUID) after
  /// a reinstall/update. Stored absolute preview paths then point nowhere and
  /// the previews look empty. Our previews always live in one folder with a
  /// deterministic file name, so re-anchor them to the current folder.
  Future<void> _rebasePreviewPaths(Map<String, dynamic> value) async =>
      rebasePreviewPaths(value, (await _directory()).path);

  @visibleForTesting
  static void rebasePreviewPaths(
    Map<String, dynamic> value,
    String currentDirectory,
  ) {
    final items = value['items'];
    if (items is! List) return;
    for (final row in items) {
      if (row is! Map) continue;
      final stored = row['previewPath'];
      if (stored is! String || stored.isEmpty) continue;
      // Only our own previews; never touch original camera/picker paths.
      if (p.basename(p.dirname(stored)) != _previewsFolder) continue;
      row['previewPath'] = p.join(currentDirectory, p.basename(stored));
    }
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      _storage.write(key: _key, value: jsonEncode(value));

  @override
  Future<String> retainPreview(String id, String sourcePath) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final name = sha256.convert(utf8.encode(id)).toString();
    final extension = p.extension(sourcePath).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : '.image';
    final target = p.join(directory.path, '$name$safeExtension');
    if (p.equals(sourcePath, target)) return target;
    await File(sourcePath).copy(target);
    return target;
  }

  @override
  Future<void> prunePreviews(Set<String> retainedPaths) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    // Delete only files owned by this feature, never the original camera media.
    // Match by file name: a moved app container must not make every still
    // referenced preview look unreferenced (and delete it).
    final retainedNames = retainedPaths.map(p.basename).toSet();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && !retainedNames.contains(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await prunePreviews({});
  }
}
