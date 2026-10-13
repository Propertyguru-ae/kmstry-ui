/// Exact, server-confirmed removals; never guess a recurring schedule locally.
class VenueEventDeletion {
  const VenueEventDeletion({
    required this.removedEventIds,
    this.removedRecurringRuleId,
  });
  final Set<String> removedEventIds;
  final String? removedRecurringRuleId;

  factory VenueEventDeletion.fromJson(
    dynamic json, {
    String? eventId,
    String? ruleId,
  }) {
    final ids = json is Map ? json['removedEventIds'] : null;
    return VenueEventDeletion(
      removedEventIds: ids is List
          ? ids.map((id) => id.toString()).toSet()
          : {?eventId},
      removedRecurringRuleId:
          json is Map && json.containsKey('removedRecurringRuleId')
          ? json['removedRecurringRuleId']?.toString()
          : ruleId,
    );
  }
}
