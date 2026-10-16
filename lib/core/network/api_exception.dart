class ApiException implements Exception {
  final int statusCode;
  final Map<String, dynamic> data;

  ApiException({required this.statusCode, required this.data});

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
    "This text doesn't meet our content guidelines. Your changes haven't been saved. Please edit it and try again.";

bool isAwsSharingPermissionDeclined(Object error) =>
    error is ApiException &&
    error.data['errorCode'] == 'AWS_SHARING_PERMISSION_DECLINED';

bool isAwsSharingPermissionError(Object error) {
  final code = error is ApiException
      ? error.data['errorCode']?.toString() ?? ''
      : error.toString();
  return code.contains('AWS_SHARING_');
}

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
  final code = error is ApiException
      ? error.data['errorCode']?.toString() ?? ''
      : error.toString();
  if (code.contains('AWS_SHARING_PERMISSION')) {
    return 'Nothing was shared. Allow AWS safety checks when you are ready to submit public content.';
  }
  if (code.contains('AWS_SHARING_NOTICE_CHANGED')) {
    return 'The safety-check information has changed. Please try again to review it.';
  }
  if (code.contains('AWS_SHARING_CHOICE_CHANGED')) {
    return 'Your privacy choice changed. Please try again to review it.';
  }
  if (code.contains('PUBLIC_TEXT_CHECK_UNAVAILABLE')) {
    return "We couldn't check this text right now. Your changes haven't been saved. Please try again.";
  }
  if (code.contains('PUBLIC_TEXT_TOO_LONG')) {
    return 'This text is too long to check. Please shorten it and try again.';
  }
  return isPublicTextRejection(error) ? publicTextRejectionMessage : fallback;
}

/// A content decision is not a system failure. Keep the title consistent with
/// the typed backend error instead of the generic error dialog default.
String publicTextErrorTitle(
  Object error, {
  String fallback = 'Something went wrong',
}) {
  final code = error is ApiException
      ? error.data['errorCode']?.toString() ?? ''
      : error.toString();
  if (code.contains('AWS_SHARING_')) return 'Safety checks permission';
  if (code.contains('PUBLIC_TEXT_CHECK_UNAVAILABLE')) {
    return 'Text check unavailable';
  }
  if (code.contains('PUBLIC_TEXT_TOO_LONG')) return 'Text too long';
  return isPublicTextRejection(error) ? 'Please edit your text' : fallback;
}
