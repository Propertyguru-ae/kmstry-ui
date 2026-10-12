import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';

void main() {
  late Directory directory;
  late File original;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-output-test-');
    original = await File(
      '${directory.path}/original.mp4',
    ).writeAsBytes([1, 2]);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'keeps a valid larger conversion instead of reverting to HEVC',
    () async {
      final output = await File(
        '${directory.path}/h264.mp4',
      ).writeAsBytes([1, 2, 3, 4]);
      expect(
        (await MediaCompressor.selectPreparedVideo(original, output.path)).path,
        output.path,
      );
    },
  );
  test('keeps a valid smaller conversion', () async {
    final output = await File('${directory.path}/h264.mp4').writeAsBytes([1]);
    expect(
      (await MediaCompressor.selectPreparedVideo(original, output.path)).path,
      output.path,
    );
  });
  test(
    'missing, empty and absent output fall back for backend normalization',
    () async {
      final empty = await File('${directory.path}/empty.mp4').writeAsBytes([]);
      for (final output in [
        null,
        '',
        empty.path,
        '${directory.path}/missing.mp4',
      ]) {
        expect(
          (await MediaCompressor.selectPreparedVideo(original, output)).path,
          original.path,
        );
      }
    },
  );
}
