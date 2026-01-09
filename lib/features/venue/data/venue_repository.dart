import 'package:kmstry_frontend/core/network/api_client.dart';
import 'venue_model.dart';

class VenueRepository {
  final ApiClient _api = ApiClient();

  Future<List<Venue>> getVenues() async {
    final data = await _api.get('/venues');

    // 👇 API LIST döndürüyor
    final list = data as List;

    return list.map((e) => Venue.fromJson(e)).toList();
  }
}
