class VenueCheckinStats {
  final String venueId;
  final int checkinCountActive;
  final int male;
  final int female;
  final DateTime? updatedAt;

  const VenueCheckinStats({
    required this.venueId,
    required this.checkinCountActive,
    required this.male,
    required this.female,
    this.updatedAt,
  });

  factory VenueCheckinStats.fromJson(Map<String, dynamic> json) {
    final breakdownRaw =
        json['checkinGenderBreakdown'] ?? json['checkin_gender_breakdown'];
    final breakdown = breakdownRaw is Map
        ? Map<String, dynamic>.from(breakdownRaw)
        : const <String, dynamic>{};
    final updatedAtRaw = json['updatedAt'] ?? json['updated_at'];
    return VenueCheckinStats(
      venueId: (json['venueId'] ?? json['venue_id'] ?? '').toString(),
      checkinCountActive: _asInt(
        json['checkinCountActive'] ?? json['checkin_count_active'],
      ),
      male: _asInt(breakdown['male']),
      female: _asInt(breakdown['female']),
      updatedAt: updatedAtRaw is String ? DateTime.tryParse(updatedAtRaw) : null,
    );
  }

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}
