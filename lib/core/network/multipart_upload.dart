import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const Duration defaultMultipartUploadTimeout = Duration(minutes: 2);

/// Sends one multipart request through a dedicated client. The response body
/// is buffered before the client is closed, so timeout/route disposal cannot
/// leave a reusable connection running in the background.
Future<http.StreamedResponse> sendMultipartRequest(
  http.MultipartRequest request, {
  Duration timeout = defaultMultipartUploadTimeout,
}) async {
  final client = http.Client();
  try {
    final streamed = await client.send(request).timeout(timeout);
    final bytes = await streamed.stream
        .fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
          builder.add(chunk);
          return builder;
        })
        .timeout(timeout);
    final body = bytes.takeBytes();
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
    client.close();
  }
}
