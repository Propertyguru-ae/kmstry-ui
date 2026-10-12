import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';

class ProfileStats {
  const ProfileStats({required this.friends, required this.venues});
  final int friends;
  final int venues;
}

class ProfileStatsRepository {
  ProfileStatsRepository({
    ApiClient? api,
    Future<String?> Function()? tokenProvider,
  }) : _api = api ?? ApiClient(),
       _tokenProvider = tokenProvider ?? SecureStorage.getAccessToken;

  final ApiClient _api;
  final Future<String?> Function() _tokenProvider;

  Future<ProfileStats> load() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) throw StateError('Not authenticated');
    final data = await _api.get(
      '/users/me/social-stats',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map ||
        data['friendCount'] is! num ||
        data['followedVenueCount'] is! num) {
      throw const FormatException('Invalid profile stats');
    }
    return ProfileStats(
      friends: (data['friendCount'] as num).toInt(),
      venues: (data['followedVenueCount'] as num).toInt(),
    );
  }
}
