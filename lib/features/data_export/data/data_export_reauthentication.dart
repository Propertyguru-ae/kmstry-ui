import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class DataExportReauthentication {
  DataExportReauthentication({AuthRepository? auth})
    : _auth = auth ?? AuthRepository();

  final AuthRepository _auth;

  Future<void> withPassword({
    required String email,
    required String password,
  }) => _protectIdentity(() => _auth.login(email, password));

  Future<void> withGoogle() => _protectIdentity(() => _auth.loginWithGoogle());

  Future<void> withApple() => _protectIdentity(() => _auth.loginWithApple());

  Future<void> _protectIdentity(Future<bool> Function() authenticate) async {
    final previousAccess = await SecureStorage.getAccessToken();
    final previousRefresh = await SecureStorage.getRefreshToken();
    final before = await _auth.getMe();
    final beforeId = _userId(before);
    if (beforeId == null) {
      throw Exception('Current account could not be verified');
    }

    try {
      final completed = await authenticate();
      if (!completed) throw Exception('Authentication was cancelled');
      AuthRepository.invalidateMeCache();
      final after = await _auth.getMe();
      if (_userId(after) != beforeId) {
        throw Exception('Please authenticate with the same KMSTRY account');
      }
    } catch (_) {
      if (previousAccess != null && previousRefresh != null) {
        await SecureStorage.saveTokens(
          accessToken: previousAccess,
          refreshToken: previousRefresh,
        );
      }
      AuthRepository.invalidateMeCache();
      rethrow;
    }
  }

  String? _userId(Map<String, dynamic> response) {
    final candidates = <Map<String, dynamic>>[
      response,
      if (response['data'] is Map)
        Map<String, dynamic>.from(response['data'] as Map),
      if (response['user'] is Map)
        Map<String, dynamic>.from(response['user'] as Map),
    ];
    final data = response['data'];
    if (data is Map && data['user'] is Map) {
      candidates.add(Map<String, dynamic>.from(data['user'] as Map));
    }
    for (final candidate in candidates) {
      final id = candidate['id'] ?? candidate['userId'] ?? candidate['user_id'];
      final normalized = id?.toString().trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }
}
