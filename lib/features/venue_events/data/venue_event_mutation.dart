import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

/// Server-committed changes, not optimistic guesses about a recurring schedule.
class VenueEventMutation {
  static const _detailFields = [
    'description',
    'photo',
    'photos',
    'currency',
    'capacity',
    'priceAed',
    'recurringRuleId',
    'recurrence',
    'rsvpCount',
    'partnershipCount',
    'partnershipBenefits',
    'offerId',
    'offerTitle',
    'offerType',
    'offerPrice',
    'offerDiscountValue',
  ];
  final VenueUpcomingEvent event;
  final List<VenueUpcomingEvent> events;
  final Set<String> removedEventIds;

  /// Compatibility fallback for older/incomplete API responses. Current writes
  /// atomically commit metadata, benefits and offers and return final details.
  final bool requiresDetailRefresh;

  const VenueEventMutation({
    required this.event,
    required this.events,
    this.removedEventIds = const {},
    this.requiresDetailRefresh = false,
  });

  factory VenueEventMutation.fromJson(Map<String, dynamic> json) {
    final event = VenueUpcomingEvent.fromJson(json);
    final changes = json['eventChanges'];
    final rows = changes is Map ? changes['events'] : null;
    final removed = changes is Map ? changes['removedEventIds'] : null;
    return VenueEventMutation(
      event: event,
      events: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) => VenueUpcomingEvent.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList()
          : [event],
      removedEventIds: removed is List
          ? removed.map((id) => id.toString()).toSet()
          : const {},
      // Retain the previous detail re-read on older/incomplete API responses.
      // Explicit null/empty fields are authoritative; missing fields are not.
      requiresDetailRefresh: !_detailFields.every(json.containsKey),
    );
  }

  List<VenueUpcomingEvent> applyTo(List<VenueUpcomingEvent> current) {
    final byId = {
      for (final row in current)
        if (!removedEventIds.contains(row.id)) row.id: row,
    };
    for (final row in events) {
      byId[row.id] = row;
    }
    return byId.values.toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }
}
