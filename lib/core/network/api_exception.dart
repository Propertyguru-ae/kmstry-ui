class ApiException implements Exception {
  final int statusCode;
  final Map<String, dynamic> data;

  ApiException({
    required this.statusCode,
    required this.data,
  });

  @override
  String toString() {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    if (message is List && message.isNotEmpty) {
      final first = message.first;
      final asText = first?.toString().trim() ?? '';
      if (asText.isNotEmpty) {
        return asText;
      }
    }
    return 'ApiException';
  }
}

const publicTextRejectionMessage =
    'This text cannot be published. Please edit it and try again.';

/// Stable mapping for the backend's public UGC filter contract. Multipart
/// repositories currently wrap response JSON in an Exception, so the fallback
/// string check keeps upload flows consistent too.
bool isPublicTextRejection(Object error) {
  if (error is ApiException) {
    return error.data['errorCode']?.toString() == 'PUBLIC_TEXT_NOT_ALLOWED';
  }
  return error.toString().contains('PUBLIC_TEXT_NOT_ALLOWED');
}

String publicTextErrorMessage(Object error, {required String fallback}) {
  return isPublicTextRejection(error) ? publicTextRejectionMessage : fallback;
}
