import 'package:firebase_core/firebase_core.dart';
// Firebase's official platform-channel test adapter; no real project/network.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/chat/presentation/chat_media_frame.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImageRepository extends ChatRepository {
  _ImageRepository(this.messages) : super(cache: ChatMemoryCache());

  final List<ChatMessage> messages;

  @override
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) async => ChatDetail(id: chatId, messages: messages);

  @override
  Future<void> markChatRead(String chatId) async {}
}

ChatMessage _image(
  String id, {
  required bool isMe,
  int? width,
  int? height,
  bool remote = false,
}) => ChatMessage(
  id: id,
  messageType: 'image',
  imageUrl: remote
      ? 'https://example.invalid/$id.png'
      : '/chat-image-test/$id.png',
  imageWidth: width,
  imageHeight: height,
  isMe: isMe,
  createdAt: DateTime(2026, 10, 2, 12),
);

Future<void> _openChat(
  WidgetTester tester,
  List<ChatMessage> messages, {
  double screenWidth = 393,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(screenWidth, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MessageDetailPage(
        chatId: 'image-chat',
        otherUserId: 'other',
        otherName: 'Other User',
        otherPhotoUrl: '',
        repository: _ImageRepository(messages),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  const frameKey = ValueKey('chat-image-preview-frame');

  test('ratio picks one of three fixed frames; unknown sizes are square', () {
    const screen = Size(393, 1600);
    final width = 393 * 0.68 - 9.2;
    void expectFrame(int? w, int? h, double height) {
      final size = chatMediaFrameSize(screen, imageWidth: w, imageHeight: h);
      expect(size.width, closeTo(width, 0.001));
      expect(size.height, closeTo(height, 0.001));
    }

    expectFrame(600, 1200, width * 330 / 260);
    expectFrame(1080, 1350, width * 330 / 260);
    expectFrame(600, 600, width);
    expectFrame(1000, 1100, width);
    expectFrame(null, null, width);
    expectFrame(1200, 600, width * 0.75);
    expectFrame(3000, 300, width * 0.75);
  });

  for (final isMe in [false, true]) {
    testWidgets(
      '${isMe ? 'outgoing' : 'incoming'} images use fixed frames with a common width',
      (tester) async {
        await _openChat(tester, [
          _image('portrait', isMe: isMe, width: 600, height: 1200),
          _image('landscape', isMe: isMe, width: 1200, height: 600),
          _image('square', isMe: isMe, width: 600, height: 600),
          _image('panorama', isMe: isMe, width: 3000, height: 300),
          _image('unknown', isMe: isMe),
        ]);
        final frames = find.byKey(frameKey);
        expect(frames, findsNWidgets(5));
        final width = 393 * 0.68 - 9.2;
        final cases = {
          'portrait': width * 330 / 260,
          'landscape': width * 0.75,
          'square': width,
          'panorama': width * 0.75,
          'unknown': width,
        };
        for (final entry in cases.entries) {
          final frame = find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Hero && widget.tag == 'chat-media-${entry.key}',
            ),
            matching: find.byKey(frameKey),
          );
          final size = tester.getSize(frame);
          expect(size.width, closeTo(width, 0.001));
          expect(size.height, closeTo(entry.value, 0.001));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('small screens shrink the frame to fit inside the bubble', (
    tester,
  ) async {
    await _openChat(tester, [
      _image('portrait', isMe: true, width: 600, height: 1200),
    ], screenWidth: 320);
    final size = tester.getSize(find.byKey(frameKey));
    expect(size.width + 9.2, closeTo(320 * 0.68, 0.001));
    expect(size.height, closeTo(size.width * 330 / 260, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large screens cap the frame width at 260', (tester) async {
    await _openChat(tester, [
      _image('landscape', isMe: false, width: 1200, height: 600),
    ], screenWidth: 800);
    expect(tester.getSize(find.byKey(frameKey)), const Size(260, 195));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('local upload and remote download reserve the same frame', (
    tester,
  ) async {
    await _openChat(tester, [
      _image('temp-upload', isMe: true, width: 600, height: 1200),
      _image('received', isMe: false, width: 600, height: 1200, remote: true),
    ]);
    final frames = find.byKey(frameKey);
    expect(frames, findsNWidgets(2));
    final initialSize = tester.getSize(frames.first);
    expect(tester.getSize(frames.last), initialSize);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSize(frames.first), initialSize);
    expect(tester.getSize(frames.last), initialSize);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'thumbnail fills the frame, fullscreen viewer shows the full image',
    (tester) async {
      await _openChat(tester, [
        _image('portrait', isMe: true, width: 600, height: 1200),
      ]);
      // WhatsApp-style: the bubble fills its fixed frame (cover); the fullscreen
      // viewer shows the whole image (contain).
      final previewImage = find.descendant(
        of: find.byKey(frameKey),
        matching: find.byType(Image),
      );
      expect(previewImage, findsOneWidget);
      expect(tester.widget<Image>(previewImage).fit, BoxFit.cover);
      await tester.tap(find.byKey(frameKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final fullscreen = find.byType(InteractiveViewer);
      expect(fullscreen, findsOneWidget);
      final fullImage = find.descendant(
        of: fullscreen,
        matching: find.byType(Image),
      );
      expect(tester.widget<Image>(fullImage).fit, BoxFit.contain);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
