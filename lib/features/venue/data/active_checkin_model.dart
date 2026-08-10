class ActiveCheckin {
  final String id;
  final String venueId;
  final DateTime? expiresAt;

  ActiveCheckin({
    required this.id,
    required this.venueId,
    this.expiresAt,
  });

  factory ActiveCheckin.fromJson(Map<String, dynamic> json) {
    // Handle both snake_case and camelCase field names
    final venueId = json['venue_id'] as String? ?? 
                    json['venueId'] as String? ??
                    (json['venue'] != null && json['venue'] is Map 
                        ? (json['venue'] as Map)['id'] as String? 
                        : null);
    
    if (venueId == null) {
      throw Exception('ActiveCheckin missing venue_id field');
    }
    
    return ActiveCheckin(
      id: json['id'] as String,
      venueId: venueId,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : json['expiresAt'] != null
              ? DateTime.parse(json['expiresAt'] as String)
              : null,
    );
  }

  bool get isActive {
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }
}
