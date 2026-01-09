class Venue {
  final String id;
  final String name;
  final String type;
  final String status;     // UI derived
  final String address;
  final String city;
  final String photoUrl;
  final double latitude;
  final double longitude;
  final String tag;        // UI derived

  Venue({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.address,
    required this.city,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.tag,
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    return Venue(
      id: json['id'],
      name: json['name'],
      type: json['type'], // enum string olarak gelir
      address: json['address'],
      city: json['city'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      photoUrl: json['photo'],

      // 👇 UI için geçici/hesaplanan alanlar
      status: _computeStatus(json),
      tag: _computeTag(json),
    );
  }

  // ---------- UI HELPERS ----------

  static String _computeStatus(Map<String, dynamic> json) {
    // MVP: sabit / dummy
    return 'Buzzing';
  }

  static String _computeTag(Map<String, dynamic> json) {
    // MVP: sabit / dummy
    return '#PopularNow';
  }
}
