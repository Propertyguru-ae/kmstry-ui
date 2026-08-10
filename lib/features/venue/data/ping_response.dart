class PingResponse {
  final String status;
  final double? distance;

  PingResponse({
    required this.status,
    this.distance,
  });

  factory PingResponse.fromJson(Map<String, dynamic> json) {
    return PingResponse(
      status: json['status'],
      distance: json['distance_from_venue'] != null
          ? (json['distance_from_venue'] as num).toDouble()
          : null,
    );
  }
}
