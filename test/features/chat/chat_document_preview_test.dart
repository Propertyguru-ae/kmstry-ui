import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
// Use the package's own method-channel adapter for deterministic native tests.
// ignore: implementation_imports
import 'package:pdfx/src/renderer/interfaces/platform.dart';
// ignore: implementation_imports
import 'package:pdfx/src/renderer/io/platform_method_channel.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_pdf_preview_service.dart';
import 'package:kmstry_frontend/features/chat/presentation/chat_document_preview_page.dart';
import 'package:kmstry_frontend/features/chat/presentation/chat_document_card.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  _Picker({this.name = 'Test report.pdf', this.size = 1024});
  final String name;
  final int size;

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
  }) async => FilePickerResult([
    PlatformFile(name: name, size: size, path: '/test/$name'),
  ]);
}

class _Repo extends ChatRepository {
  _Repo({this.messages = const []}) : super(cache: ChatMemoryCache());
  final List<ChatMessage> messages;
  int uploads = 0;
  int sends = 0;

  @override
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) async => ChatDetail(id: chatId, messages: messages);

  @override
  Future<void> markChatRead(String chatId) async {}

  @override
  Future<({String url, String objectKey, String fileName})> uploadChatFile(
    File file,
  ) async {
    uploads++;
    return (
      url: 'https://storage.example/report.pdf',
      objectKey: 'private/report.pdf',
      fileName: 'Test report.pdf',
    );
  }

  @override
  Future<ChatMessage> sendMessage(
    String chatId, {
    required String messageType,
    String? text,
    String? imageUrl,
    String? imageObjectKey,
    int? imageWidth,
    int? imageHeight,
    String? fileUrl,
    String? fileObjectKey,
    String? fileName,
    String? clientMessageId,
    String? replyToId,
    String? venueId,
    File? localUploadedImage,
  }) async {
    sends++;
    return ChatMessage(
      id: 'confirmed-document',
      messageType: messageType,
      fileUrl: fileUrl,
      fileName: fileName,
      clientMessageId: clientMessageId,
      isMe: true,
      createdAt: DateTime.now(),
    );
  }
}

Future<void> _openChat(WidgetTester tester, _Repo repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MessageDetailPage(
        chatId: 'chat',
        otherUserId: 'other',
        otherName: 'Other User',
        otherPhotoUrl: '',
        repository: repo,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _selectDocument(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Document'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _Picker();
    PdfxPlatform.instance = PdfxPlatformMethodChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('io.scer.pdf_renderer'), (
          _,
        ) async {
          throw PlatformException(code: 'PREVIEW_UNAVAILABLE');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.scer.pdf_renderer'),
          null,
        );
  });

  testWidgets(
    'PDF card shows the top of the first page, pages, size and type',
    (tester) async {
      final pixels = img.Image(width: 8, height: 12);
      final service = ChatPdfPreviewService(
        client: MockClient(
          (_) async => http.Response('%PDF-controlled test', 200),
        ),
        renderer: (_) async => ChatPdfPreview(
          bytes: Uint8List.fromList(img.encodePng(pixels)),
          pageCount: 3,
          documentBytes: 829 * 1024,
        ),
      );
      addTearDown(service.dispose);
      // Stream-based downloads run outside the widget test's fake clock.
      await tester.runAsync(
        () => service.preview(source: 'https://storage.example/report.pdf'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatDocumentCard(
                fileName: 'Report.pdf',
                source: 'https://storage.example/report.pdf',
                service: service,
                width: 240,
                isDark: false,
                textColor: Colors.black,
                meta: const Text('12:00'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 pages • 829 KB • PDF'), findsOneWidget);
      expect(find.text('Report.pdf'), findsOneWidget);
      final image = find.byType(Image);
      expect(image, findsOneWidget);
      expect(tester.widget<Image>(image).fit, BoxFit.fitWidth);
      expect(tester.widget<Image>(image).alignment, Alignment.topCenter);
      expect(
        tester.getSize(find.byKey(const ValueKey('chat-pdf-preview-frame'))),
        const Size(240, ChatDocumentCard.previewHeight),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('non-PDF documents show a typed badge without a preview', (
    tester,
  ) async {
    final service = ChatPdfPreviewService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChatDocumentCard(
              fileName: 'Budget.xlsx',
              source: 'https://storage.example/budget.xlsx',
              service: service,
              width: 240,
              isDark: true,
              textColor: Colors.white,
              meta: const Text('12:00'),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chat-pdf-preview-frame')), findsNothing);
    expect(find.text('XLSX'), findsNWidgets(2));
    expect(find.text('Budget.xlsx'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('document detail helpers', () {
    expect(documentExtensionLabel('a.PdF'), 'PDF');
    expect(documentExtensionLabel('noext'), 'FILE');
    expect(formatDocumentSize(512), '512 B');
    expect(formatDocumentSize(829 * 1024), '829 KB');
    expect(formatDocumentSize((2.5 * 1024 * 1024).round()), '2.5 MB');
    expect(documentDetailsLine(extension: 'PDF', pageCount: 1), '1 page • PDF');
  });

  for (final dark in [false, true]) {
    testWidgets(
      'preview page lays out with the real ${dark ? 'dark' : 'light'} app theme',
      (tester) async {
        // The app theme makes filled buttons full width (Size.fromHeight);
        // inside the bottom Row that used to blank the page.
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ChatDocumentPreviewPage(
                            file: File('/test/Report.docx'),
                            fileName: 'Report.docx',
                            fileSize: 2048,
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final send = find.byKey(const ValueKey('chat-document-send'));
        expect(tester.getSize(send).width, lessThan(200));
        await tester.tap(find.byTooltip('Cancel'));
        await tester.pumpAndSettle();
        expect(result, false);
        expect(find.byType(ChatDocumentPreviewPage), findsNothing);
      },
    );
  }

  testWidgets(
    'view mode (opening from chat) has no Send and Share is hidden for now',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ChatDocumentPreviewPage(
            file: File('/test/Contract.docx'),
            fileName: 'Contract.docx',
            fileSize: 4096,
            viewOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chat-document-share')), findsNothing);
      expect(find.byKey(const ValueKey('chat-document-send')), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Preview document'), findsNothing);
    },
  );

  testWidgets('selecting PDF opens confirmation and never uploads until Send', (
    tester,
  ) async {
    final repo = _Repo();
    await _openChat(tester, repo);
    await _selectDocument(tester);
    expect(find.byType(ChatDocumentPreviewPage), findsOneWidget);
    expect(find.text('Preview document'), findsOneWidget);
    expect(find.text('Test report.pdf'), findsOneWidget);
    expect(repo.uploads, 0);
    expect(repo.sends, 0);
    await tester.tap(find.byKey(const ValueKey('chat-document-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.uploads, 1);
    expect(repo.sends, 1);
    expect(
      find.byKey(const ValueKey('chat-pdf-preview-frame')),
      findsOneWidget,
    );
    expect(find.text('Test report.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cancel discards PDF without uploading or sending a message', (
    tester,
  ) async {
    final repo = _Repo();
    await _openChat(tester, repo);
    await _selectDocument(tester);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatDocumentPreviewPage), findsNothing);
    expect(find.byKey(const ValueKey('chat-pdf-preview-frame')), findsNothing);
    expect(repo.uploads, 0);
    expect(repo.sends, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'session change during confirmation prevents sending old documents',
    (tester) async {
      final repo = _Repo();
      await _openChat(tester, repo);
      await _selectDocument(tester);
      await SecureStorage.clearSession();
      await tester.tap(find.byKey(const ValueKey('chat-document-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.uploads, 0);
      expect(repo.sends, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('other document types also require explicit Send', (
    tester,
  ) async {
    FilePicker.platform = _Picker(name: 'Report.docx');
    final repo = _Repo();
    await _openChat(tester, repo);
    await _selectDocument(tester);
    expect(find.text('Document ready to send'), findsOneWidget);
    expect(repo.uploads, 0);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.sends, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('oversized selection never uploads or opens document preview', (
    tester,
  ) async {
    FilePicker.platform = _Picker(
      size: ChatPdfPreviewService.maxDocumentBytes + 1,
    );
    final repo = _Repo();
    await _openChat(tester, repo);
    await _selectDocument(tester);
    expect(find.byType(ChatDocumentPreviewPage), findsNothing);
    expect(find.text('Documents must be 25 MB or smaller.'), findsOneWidget);
    expect(repo.uploads, 0);
    expect(repo.sends, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('received PDF reserves thumbnail area even when preview fails', (
    tester,
  ) async {
    final repo = _Repo(
      messages: [
        ChatMessage(
          id: 'received-pdf',
          messageType: 'file',
          fileName: 'Long report name for a private document.pdf',
          fileUrl: 'https://storage.example/report.pdf',
          isMe: false,
          createdAt: DateTime.now(),
        ),
      ],
    );
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openChat(tester, repo);
    final frame = find.byKey(const ValueKey('chat-pdf-preview-frame'));
    expect(frame, findsOneWidget);
    expect(tester.getSize(frame).height, ChatDocumentCard.previewHeight);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
