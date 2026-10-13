import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/media/signed_media_resolver.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_pdf_preview_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pdf = Uint8List.fromList(
  utf8.encode('%PDF-1.7\ncontrolled test document'),
);
final _thumbnail = ChatPdfPreview(
  bytes: Uint8List.fromList([1, 2, 3]),
  pageCount: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'PDF detection is case insensitive and ignores other document types',
    () {
      expect(isChatPdf('Report.PDF '), true);
      expect(isChatPdf('Report.docx'), false);
      expect(isChatPdf('Report.pdf.exe'), false);
    },
  );

  test(
    'deduplicates downloads/renders and never sends JWT to storage',
    () async {
      var downloads = 0;
      var renders = 0;
      final service = ChatPdfPreviewService(
        client: MockClient((request) async {
          downloads++;
          expect(request.headers.containsKey('Authorization'), false);
          return http.Response.bytes(_pdf, 200);
        }),
        renderer: (bytes) async {
          renders++;
          return _thumbnail;
        },
      );
      addTearDown(service.dispose);
      final first = service.preview(
        source: 'https://storage.example/report.pdf',
      );
      final second = service.preview(
        source: 'https://storage.example/report.pdf',
      );
      expect(identical(first, second), true);
      expect(await first, _thumbnail);
      expect(await second, _thumbnail);
      expect(
        await service.preview(source: 'https://storage.example/report.pdf'),
        _thumbnail,
      );
      expect(downloads, 1);
      expect(renders, 1);
    },
  );

  test('refreshes a denied signed link exactly once', () async {
    var refreshes = 0;
    final requested = <String>[];
    final resolver = SignedMediaResolver(
      transport: (path) async {
        expect(path, '/chats/messages/message/media/file');
        refreshes++;
        return {
          'media_id': 'message:file',
          'temporary_url': 'https://storage.example/fresh.pdf',
          'url_expires_at': DateTime.now()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        };
      },
    );
    final service = ChatPdfPreviewService(
      resolver: resolver,
      client: MockClient((request) async {
        requested.add(request.url.path);
        return request.url.path == '/old.pdf'
            ? http.Response('', 403)
            : http.Response.bytes(_pdf, 200);
      }),
      renderer: (_) async => _thumbnail,
    );
    addTearDown(service.dispose);
    expect(
      await service.preview(
        source: 'https://storage.example/old.pdf',
        media: const MediaReference(
          mediaId: 'message:file',
          url: 'https://storage.example/old.pdf',
          refreshPath: '/chats/messages/message/media/file',
        ),
      ),
      _thumbnail,
    );
    expect(requested, ['/old.pdf', '/fresh.pdf']);
    expect(refreshes, 1);
  });

  test('does not loop when refreshed URL is also denied', () async {
    var requests = 0;
    var refreshes = 0;
    final service = ChatPdfPreviewService(
      resolver: SignedMediaResolver(
        transport: (_) async {
          refreshes++;
          return {'temporary_url': 'https://storage.example/fresh.pdf'};
        },
      ),
      client: MockClient((_) async {
        requests++;
        return http.Response('', 403);
      }),
      renderer: (_) async => _thumbnail,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.preview(
        source: 'https://storage.example/old.pdf',
        media: const MediaReference(
          mediaId: 'file',
          url: 'https://storage.example/old.pdf',
          refreshPath: '/chats/messages/file/media/file',
        ),
      ),
      throwsException,
    );
    expect(requests, 2);
    expect(refreshes, 1);
  });

  test('expired references refresh before downloading', () async {
    var refreshes = 0;
    final service = ChatPdfPreviewService(
      resolver: SignedMediaResolver(
        transport: (_) async {
          refreshes++;
          return {'temporary_url': 'https://storage.example/fresh.pdf'};
        },
      ),
      client: MockClient((request) async {
        expect(request.url.path, '/fresh.pdf');
        return http.Response.bytes(_pdf, 200);
      }),
      renderer: (_) async => _thumbnail,
    );
    addTearDown(service.dispose);
    await service.preview(
      source: 'https://storage.example/old.pdf',
      media: MediaReference(
        mediaId: 'file',
        url: 'https://storage.example/old.pdf',
        refreshPath: '/refresh',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    expect(refreshes, 1);
  });

  test('non-PDF content never reaches the native renderer', () async {
    var renders = 0;
    final service = ChatPdfPreviewService(
      client: MockClient(
        (_) async => http.Response('<html>access denied</html>', 200),
      ),
      renderer: (_) async {
        renders++;
        return _thumbnail;
      },
    );
    addTearDown(service.dispose);
    await expectLater(
      service.preview(source: 'https://storage.example/fake.pdf'),
      throwsA(isA<FormatException>()),
    );
    expect(renders, 0);
  });

  test('oversized documents are rejected before rendering', () async {
    var renders = 0;
    final service = ChatPdfPreviewService(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(_pdf),
          200,
          contentLength: ChatPdfPreviewService.maxDocumentBytes + 1,
        ),
      ),
      renderer: (_) async {
        renders++;
        return _thumbnail;
      },
    );
    addTearDown(service.dispose);
    await expectLater(
      service.preview(source: 'https://storage.example/large.pdf'),
      throwsA(isA<FormatException>()),
    );
    expect(renders, 0);
  });

  test(
    'logout discards in-flight private previews and clears cached results',
    () async {
      final rendering = Completer<ChatPdfPreview>();
      final started = Completer<void>();
      final service = ChatPdfPreviewService(
        client: MockClient((_) async => http.Response.bytes(_pdf, 200)),
        renderer: (_) {
          started.complete();
          return rendering.future;
        },
      );
      addTearDown(service.dispose);
      final future = service.preview(
        source: 'https://storage.example/report.pdf',
      );
      final rejected = expectLater(future, throwsA(isA<StateError>()));
      await started.future;
      await SecureStorage.clearSession();
      rendering.complete(_thumbnail);
      await rejected;
    },
  );

  test('thumbnail cache evicts old entries and remains bounded', () async {
    var renders = 0;
    final service = ChatPdfPreviewService(
      client: MockClient((_) async => http.Response.bytes(_pdf, 200)),
      renderer: (_) async {
        renders++;
        return _thumbnail;
      },
    );
    addTearDown(service.dispose);
    for (var i = 0; i < 25; i++) {
      await service.preview(source: 'https://storage.example/$i.pdf');
    }
    expect(renders, 25);
    await service.preview(source: 'https://storage.example/24.pdf');
    expect(renders, 25);
    await service.preview(source: 'https://storage.example/0.pdf');
    expect(renders, 26);
  });

  group('documentFile (open in app, never in a browser)', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('chat_docs_test'));
    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test(
      'downloads once into a private temp file with the original name',
      () async {
        var downloads = 0;
        final service = ChatPdfPreviewService(
          client: MockClient((request) async {
            downloads++;
            expect(request.headers.containsKey('Authorization'), false);
            return http.Response.bytes(_pdf, 200);
          }),
          temporaryDirectory: () async => temp,
        );
        addTearDown(service.dispose);
        final file = await service.documentFile(
          source: 'https://storage.example/report.pdf',
          fileName: 'Q3 report.pdf',
        );
        expect(file.path, startsWith(temp.path));
        expect(file.path, endsWith('/Q3 report.pdf'));
        expect(await file.readAsBytes(), _pdf);
        final again = await service.documentFile(
          source: 'https://storage.example/report.pdf',
          fileName: 'Q3 report.pdf',
        );
        expect(again.path, file.path);
        expect(downloads, 1);
      },
    );

    test('file names cannot escape the documents folder', () async {
      final service = ChatPdfPreviewService(
        client: MockClient((_) async => http.Response.bytes(_pdf, 200)),
        temporaryDirectory: () async => temp,
      );
      addTearDown(service.dispose);
      final file = await service.documentFile(
        source: 'https://storage.example/x.pdf',
        fileName: '../../etc/passwd',
      );
      expect(
        file.parent.parent.path,
        endsWith(
          'chat_documents/'
          '${file.parent.parent.path.split('/').last}',
        ),
      );
      expect(file.uri.pathSegments.last, '.._.._etc_passwd');
    });

    test('a failed download can be retried', () async {
      var calls = 0;
      final service = ChatPdfPreviewService(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 500)
              : http.Response.bytes(_pdf, 200);
        }),
        temporaryDirectory: () async => temp,
      );
      addTearDown(service.dispose);
      await expectLater(
        service.documentFile(
          source: 'https://storage.example/r.pdf',
          fileName: 'r.pdf',
        ),
        throwsA(isA<FormatException>()),
      );
      final file = await service.documentFile(
        source: 'https://storage.example/r.pdf',
        fileName: 'r.pdf',
      );
      expect(await file.exists(), true);
      expect(calls, 2);
    });

    test(
      'an already local (just sent) file is used without downloading',
      () async {
        final local = File('${temp.path}/sent.pdf')..writeAsBytesSync(_pdf);
        final service = ChatPdfPreviewService(
          client: MockClient((_) async => fail('must not download')),
          temporaryDirectory: () async => temp,
        );
        addTearDown(service.dispose);
        final file = await service.documentFile(
          source: 'https://storage.example/sent.pdf',
          fileName: 'sent.pdf',
          localPath: local.path,
        );
        expect(file.path, local.path);
      },
    );

    test('downloaded documents are deleted when the session ends', () async {
      final service = ChatPdfPreviewService(
        client: MockClient((_) async => http.Response.bytes(_pdf, 200)),
        temporaryDirectory: () async => temp,
      );
      addTearDown(service.dispose);
      final file = await service.documentFile(
        source: 'https://storage.example/s.pdf',
        fileName: 's.pdf',
      );
      expect(await file.exists(), true);
      service.clear();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await file.exists(), false);
    });
  });
}
