import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/network/multipart_upload.dart';

class _Client extends http.BaseClient {
  _Client(this.response);
  final Future<http.StreamedResponse> Function() response;
  int closed = 0;
  Completer<http.StreamedResponse>? pending;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    return response();
  }

  @override
  void close() {
    closed++;
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(http.ClientException('Cancelled'));
    }
  }
}

http.MultipartRequest _request() =>
    http.MultipartRequest('POST', Uri.parse('https://example.test/stories'));

void main() {
  test(
    'finishing a 401 attempt leaves cancellation usable for its retry',
    () async {
      final cancellation = MultipartUploadCancellation();
      final first = _Client(
        () async => http.StreamedResponse(Stream.value(utf8.encode('{}')), 401),
      );
      final retry = _Client(
        () async => http.StreamedResponse(Stream.value(utf8.encode('{}')), 201),
      );
      expect(
        (await sendMultipartRequest(
          _request(),
          cancellation: cancellation,
          clientFactory: () => first,
        )).statusCode,
        401,
      );
      expect(
        (await sendMultipartRequest(
          _request(),
          cancellation: cancellation,
          clientFactory: () => retry,
        )).statusCode,
        201,
      );
      expect(first.closed, 1);
      expect(retry.closed, 1);
      expect(cancellation.isCancelled, false);
    },
  );

  test('cancelling a retry closes only its active HTTP client', () async {
    final cancellation = MultipartUploadCancellation();
    final first = _Client(
      () async => http.StreamedResponse(Stream.value([1]), 401),
    );
    await sendMultipartRequest(
      _request(),
      cancellation: cancellation,
      clientFactory: () => first,
    );
    final waiting = Completer<http.StreamedResponse>();
    final started = Completer<void>();
    final retry = _Client(() {
      started.complete();
      return waiting.future;
    })..pending = waiting;
    final sending = sendMultipartRequest(
      _request(),
      cancellation: cancellation,
      clientFactory: () => retry,
    );
    final failure = expectLater(sending, throwsA(isA<http.ClientException>()));
    await started.future;
    cancellation.cancel();
    await failure;
    expect(first.closed, 1);
    expect(retry.closed, 2); // Cancellation + the normal finally cleanup.
  });

  test('already cancelled upload cannot allocate another client', () async {
    final cancellation = MultipartUploadCancellation()..cancel();
    await expectLater(
      sendMultipartRequest(
        _request(),
        cancellation: cancellation,
        clientFactory: () => throw StateError('must not create client'),
      ),
      throwsA(isA<PublicMediaUploadCancelled>()),
    );
  });
}
