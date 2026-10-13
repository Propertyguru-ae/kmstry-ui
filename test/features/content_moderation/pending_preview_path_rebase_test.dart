import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media_store.dart';

void main() {
  test('previews survive the iOS app container moving after a reinstall', () {
    const oldDir =
        '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Caches/kmstry_upload_previews_v1';
    const newDir =
        '/var/mobile/Containers/Data/Application/NEW-UUID/Library/Caches/kmstry_upload_previews_v1';
    final value = <String, dynamic>{
      'items': [
        {'id': 'a', 'previewPath': '$oldDir/abc123.jpg'},
        // Original picker media is never rewritten.
        {'id': 'b', 'previewPath': '/private/var/tmp/picker/IMG_1.heic'},
        {'id': 'c'},
      ],
    };
    DevicePendingPublicMediaStore.rebasePreviewPaths(value, newDir);
    final items = value['items'] as List;
    expect(items[0]['previewPath'], '$newDir/abc123.jpg');
    expect(items[1]['previewPath'], '/private/var/tmp/picker/IMG_1.heic');
    expect(items[2].containsKey('previewPath'), isFalse);
  });
}
