import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

const Duration defaultMultipartUploadTimeout = Duration(minutes: 2);

typedef MultipartUploadProgress = void Function(int sentBytes, int totalBytes);

/// A route-independent signal. Cancel only after the server has durably
/// cancelled the story, so an accepted request cannot become an orphan post.
class MultipartUploadCancellation {
  final Set<void Function()> _listeners = {};
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Each HTTP attempt detaches its own listener. Finishing a rejected attempt
  /// must not disable cancellation of the authenticated retry.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (isCancelled) throw const PublicMediaUploadCancelled();
  }
}

class PublicMediaUploadCancelled implements Exception {
  const PublicMediaUploadCancelled();
}

/// Builds a multipart file whose byte stream reports upload progress.
///
/// The callback tracks the primary file payload (not the small multipart
/// headers), which is the useful progress signal for large videos.
Future<http.MultipartFile> multipartFileWithProgress({
  required String field,
  required File file,
  MediaType? contentType,
  MultipartUploadProgress? onProgress,
}) async {
  if (onProgress == null) {
    return http.MultipartFile.fromPath(
      field,
      file.path,
      contentType: contentType,
    );
  }

  final total = await file.length();
  var sent = 0;
  final stream = file.openRead().transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        onProgress(sent, total);
        sink.add(chunk);
      },
    ),
  );
  return http.MultipartFile(
    field,
    http.ByteStream(stream),
    total,
    filename: path.basename(file.path),
    contentType: contentType,
  );
}

/// Sends one multipart request through a dedicated client. The response body
/// is buffered before the client is closed, so timeout/route disposal cannot
/// leave a reusable connection running in the background.
Future<http.StreamedResponse> sendMultipartRequest(
  http.MultipartRequest request, {
  Duration timeout = defaultMultipartUploadTimeout,
  MultipartUploadCancellation? cancellation,
  http.Client Function()? clientFactory,
}) async {
  cancellation?.throwIfCancelled();
  final client = (clientFactory ?? http.Client.new)();
  final detach = cancellation?.listen(client.close);
  try {
    final streamed = await client.send(request).timeout(timeout);
    final bytes = await streamed.stream
        .fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
          builder.add(chunk);
          return builder;
        })
        .timeout(timeout);
    final body = bytes.takeBytes();
    cancellation?.throwIfCancelled();
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      streamed.statusCode,
      contentLength: body.length,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  } finally {
    detach?.call();
    client.close();
  }
}
