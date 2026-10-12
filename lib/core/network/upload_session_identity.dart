import 'dart:convert';

/// Cache/session partitioning only. The server still validates the JWT.
String? uploadTokenOwner(String? token) {
  if (token == null || token.isEmpty) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final subject = payload is Map ? payload['sub'] : null;
    return subject is String && subject.isNotEmpty ? subject : null;
  } catch (_) {
    return null;
  }
}

bool sameUploadOwner(String originalToken, String? currentToken) {
  final owner = uploadTokenOwner(originalToken);
  return owner != null && owner == uploadTokenOwner(currentToken);
}
