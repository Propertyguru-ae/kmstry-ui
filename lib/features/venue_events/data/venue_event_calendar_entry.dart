class VenueEventCalendarEntry {
  const VenueEventCalendarEntry({
    required this.id,
    required this.startAt,
    this.recurringRuleId,
  });

  final String id;
  final DateTime startAt;
  final String? recurringRuleId;

  factory VenueEventCalendarEntry.fromJson(Map<String, dynamic> json) =>
      VenueEventCalendarEntry(
        id: json['id'] as String,
        startAt: DateTime.parse(json['startAt'] as String),
        recurringRuleId: json['recurringRuleId'] as String?,
      );
}
