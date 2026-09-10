class PingResponse {
  final String status;
  final double? distance;

  /// status == 'expired' iken: kullanıcı hâlâ mekanda mı (≤200m) ve mekan bilgisi.
  /// "Hâlâ buradaysan yenile" popup'ı yalnızca [nearVenue] true ise gösterilir.
  final bool nearVenue;
  final String? venueId;
  final String? venueName;

  PingResponse({
    required this.status,
    this.distance,
    this.nearVenue = false,
    this.venueId,
    this.venueName,
  });

  factory PingResponse.fromJson(Map<String, dynamic> json) {
    return PingResponse(
      status: json['status'],
      distance: json['distance_from_venue'] != null
          ? (json['distance_from_venue'] as num).toDouble()
          : null,
      nearVenue: json['near_venue'] == true,
      venueId: json['venue_id']?.toString(),
      venueName: json['venue_name']?.toString(),
    );
  }
}
