import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_picker.dart';

class _Picker extends FilePicker {
  FilePickerResult? result;
  FileType? requestedType;
  bool? multiple;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    requestedType = type;
    multiple = allowMultiple;
    return result;
  }
}

void main() {
  late _Picker picker;
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });

  test('both gallery entry points use a multiple-image picker', () async {
    picker.result = FilePickerResult([
      for (final name in ['photo.jpg', 'portrait.PNG', 'camera.heic'])
        PlatformFile(name: name, size: 10, path: '/test/$name'),
    ]);
    final files = await pickVenueGalleryMedia();
    expect(picker.requestedType, FileType.image);
    expect(picker.multiple, isTrue);
    expect(files.map((file) => file.path), [
      '/test/photo.jpg',
      '/test/portrait.PNG',
      '/test/camera.heic',
    ]);
  });

  test(
    'stale videos and unsupported picker results never reach upload',
    () async {
      picker.result = FilePickerResult([
        for (final name in [
          'clip.mp4',
          'clip.MOV',
          'clip.m4v',
          'clip.3gp',
          'clip.webm',
          'clip.mkv',
          'clip.avi',
          'clip.mpeg',
          'clip.mpg',
          'file.pdf',
          'photo.jpg',
        ])
          PlatformFile(name: name, size: 10, path: '/test/$name'),
        PlatformFile(name: 'no-path.jpg', size: 10),
      ]);
      expect((await pickVenueGalleryMedia()).map((file) => file.path), [
        '/test/photo.jpg',
      ]);
    },
  );

  test('cancelling the picker creates no upload', () async {
    expect(await pickVenueGalleryMedia(), isEmpty);
  });
}
