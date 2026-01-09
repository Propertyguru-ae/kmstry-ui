class ApiException implements Exception {
  final int statusCode;
  final Map<String, dynamic> data;

  ApiException({
    required this.statusCode,
    required this.data,
  });

  @override
  String toString() {
    return data['message'] ?? 'ApiException';
  }
}
