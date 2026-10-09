import 'dart:io';

/// Process-local checksum cache for private, immutable model files.
/// A new process or any file metadata change requires full verification again.
class VerifiedModelCache {
  final _verified = <String, (String, int, DateTime, DateTime)>{};

  Future<File?> find(
    String key, {
    required Future<File?> Function() locate,
    required Future<File?> Function() verify,
  }) async {
    final file = await locate();
    if (file == null) {
      _verified.remove(key);
      return null;
    }
    final before = await file.stat();
    final stamp = (file.path, before.size, before.modified, before.changed);
    if (before.type == FileSystemEntityType.file && _verified[key] == stamp) {
      return file;
    }
    _verified.remove(key);
    final valid = await verify();
    if (valid != null) {
      final after = await valid.stat();
      final current = (valid.path, after.size, after.modified, after.changed);
      if (after.type != FileSystemEntityType.file || current != stamp) {
        throw StateError(
          'The speech model changed during verification. Retry.',
        );
      }
      _verified[key] = current;
    }
    return valid;
  }

  void clear() => _verified.clear();
}
