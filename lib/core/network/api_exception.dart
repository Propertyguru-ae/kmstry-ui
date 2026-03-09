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
