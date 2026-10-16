import 'dart:async';
import 'dart:io';

// Platform fakes exercise the real CameraController without native hardware.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:image/image.dart' as img;
import 'package:kmstry_frontend/core/media/public_media_upload_policy.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/camera/presentation/preview_screen.dart';
import 'package:kmstry_frontend/main.dart' as app;
import 'package:permission_handler/permission_handler.dart';

class _Camera extends CameraPlatform {
  final audioSettings = <bool>[];
  final lenses = <CameraLensDirection>[];
  int photos = 0;
  int videos = 0;
  String? photoPath;

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    audioSettings.add(enableAudio);
    lenses.add(description.lensDirection);
    return audioSettings.length;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      Stream.fromFuture(Completer<CameraErrorEvent>().future);
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose(int cameraId) async {}
  @override
  Future<XFile> takePicture(int cameraId) async {
    photos++;
    if (photoPath != null) return XFile(photoPath!);
    throw CameraException('TEST_CAPTURE', 'No fixture required');
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    videos++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Camera camera;
  late CameraPlatform previousCamera;
  final permissionCalls = <MethodCall>[];
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const volumeShutter = MethodChannel('app/volume_shutter');

  setUp(() {
    previousCamera = CameraPlatform.instance;
    camera = _Camera();
    CameraPlatform.instance = camera;
    app.cameras = const [
      CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 0,
      ),
    ];
    permissionCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeShutter, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async {
          permissionCalls.add(call);
          if (call.method == 'requestPermissions') {
            return {
              for (final permission in call.arguments as List) permission: 1,
            };
          }
          return 1;
        });
  });
  tearDown(() async {
    CameraPlatform.instance = previousCamera;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeShutter, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
  });

  test(
    'public camera is photo-only independently of the deployment environment',
    () {
      expect(PublicMediaUploadPolicy.allowVideo, isFalse);
      expect(const CameraScreen.publicMedia().allowVideo, isFalse);
      expect(const CameraScreen().allowVideo, isFalse);
      expect(const CameraScreen.publicMedia().requiresSharingPermission, isTrue);
      expect(const CameraScreen().requiresSharingPermission, isFalse);
    },
  );

  testWidgets(
    'front/back photo cameras never enable audio or request a microphone',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CameraScreen.publicMedia(useFrontCamera: true)),
      );
      await tester.pumpAndSettle();
      final shutter = find.byKey(const ValueKey('camera-shutter'));
      final gesture = tester.widget<GestureDetector>(shutter);
      expect(gesture.onTap, isNotNull);
      expect(gesture.onLongPressStart, isNull);
      expect(gesture.onLongPressEnd, isNull);
      expect(gesture.onLongPressCancel, isNull);
      await tester.longPress(shutter);
      await tester.pumpAndSettle();
      expect(camera.videos, 0);
      await tester.tap(find.byIcon(Icons.cameraswitch));
      await tester.pumpAndSettle();
      expect(camera.lenses, [
        CameraLensDirection.front,
        CameraLensDirection.back,
      ]);
      expect(camera.audioSettings, [false, false]);
      expect(
        permissionCalls.every(
          (call) =>
              call.method == 'requestPermissions' &&
              (call.arguments as List).single == Permission.camera.value,
        ),
        isTrue,
      );
      final before = camera.photos;
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(camera.photos, before + 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'photo capture still opens the editor and Retake returns to camera',
    (tester) async {
      late Directory directory;
      // Exercise the actual photo processing and editor with a small JPEG fixture.
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'kmstry-photo-camera-',
        );
        final source = File('${directory.path}/capture.jpg');
        await source.writeAsBytes(
          img.encodeJpg(img.Image(width: 12, height: 16)),
        );
        camera.photoPath = source.path;
      });
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        const MaterialApp(home: CameraScreen.publicMedia()),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('camera-shutter')));
        // Let the file copy/read/write futures finish outside the fake clock.
        for (
          var i = 0;
          i < 30 && find.byType(PreviewScreen).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(PreviewScreen), findsOneWidget);
      expect(find.text('Use'), findsOneWidget);
      FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
      PublicContentPermission.onRequired = (_) async => throw ApiException(
        statusCode: 403, data: const {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
      );
      addTearDown(() => PublicContentPermission.onRequired = null);
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewScreen), findsOneWidget);
      expect(find.text('Nothing was shared. Allow safety checks to continue.'), findsOneWidget);
      expect(find.text('Review permission'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-shutter')), findsOneWidget);
      expect(camera.videos, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
