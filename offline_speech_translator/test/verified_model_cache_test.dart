import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/data/verified_model_cache.dart';

void main() {
  late Directory directory;
  late File model;
  late VerifiedModelCache cache;
  var verifications = 0;
  Future<File?> locate() async => await model.exists() ? model : null;
  Future<File?> verify() async {
    verifications++;
    if (await model.readAsString() != 'verified weights') {
      throw const FormatException('Checksum mismatch');
    }
    return model;
  }

  Future<File?> find() =>
      cache.find('expected-checksum', locate: locate, verify: verify);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('speech-cache-test');
    model = File('${directory.path}/model.bin');
    await model.writeAsString('verified weights');
    cache = VerifiedModelCache();
    verifications = 0;
  });
  tearDown(() => directory.delete(recursive: true));

  test('verifies once per unchanged file, again after cache clear', () async {
    expect(await find(), model);
    expect(await find(), model);
    expect(verifications, 1);
    cache.clear();
    expect(await find(), model);
    expect(verifications, 2);
  });

  test(
    'changed and corrupt files cannot reuse a previous verification',
    () async {
      await find();
      await model.writeAsString('corrupt weights');
      await expectLater(find(), throwsFormatException);
      await expectLater(find(), throwsFormatException);
      expect(verifications, 3);
    },
  );

  test('same-size file change also requires verification', () async {
    await find();
    await model.writeAsString('corrupt! weights');
    await model.setLastModified(DateTime(2030));
    await expectLater(find(), throwsFormatException);
  });

  test('missing files invalidate the cached entry', () async {
    await find();
    await model.delete();
    expect(await find(), isNull);
    await model.writeAsString('verified weights');
    expect(await find(), model);
    expect(verifications, 2);
  });

  test('rejects a file that changes during verification', () async {
    await expectLater(
      cache.find(
        'key',
        locate: locate,
        verify: () async {
          await model.writeAsString('changed during checksum');
          return model;
        },
      ),
      throwsStateError,
    );
    await expectLater(find(), throwsFormatException);
  });
}
