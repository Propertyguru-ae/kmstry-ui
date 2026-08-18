import 'package:flutter/foundation.dart';

/// Advanced Filters (KMSTRY+) state for the "who's here" attendee list.
/// Immutable value object; `toQueryParameters` serialises to the backend
/// query contract on GET /venues/:id/checkins.
@immutable
class AttendeeFilter {
  final String? gender; // 'male' | 'female'
  final int? minAge;
  final int? maxAge;
  final String? vibe;
  final String? intent;
  final List<String> intents;

  const AttendeeFilter({
    this.gender,
    this.minAge,
    this.maxAge,
    this.vibe,
    this.intent,
    this.intents = const [],
  });

  static const empty = AttendeeFilter();

  List<String> get effectiveIntents {
    if (intents.isNotEmpty) return intents;
    final legacyIntent = intent;
    if (legacyIntent == null || legacyIntent.isEmpty) return const [];
    return [legacyIntent];
  }

  bool get isEmpty =>
      gender == null &&
      minAge == null &&
      maxAge == null &&
      (vibe == null || vibe!.isEmpty) &&
      effectiveIntents.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Number of active filter facets — drives the badge on the filter button.
  int get activeCount {
    var n = 0;
    if (gender != null) n++;
    if (minAge != null || maxAge != null) n++;
    if (vibe != null && vibe!.isNotEmpty) n++;
    if (effectiveIntents.isNotEmpty) n++;
    return n;
  }

  AttendeeFilter copyWith({
    Object? gender = _sentinel,
    Object? minAge = _sentinel,
    Object? maxAge = _sentinel,
    Object? vibe = _sentinel,
    Object? intent = _sentinel,
    Object? intents = _sentinel,
  }) {
    return AttendeeFilter(
      gender: gender == _sentinel ? this.gender : gender as String?,
      minAge: minAge == _sentinel ? this.minAge : minAge as int?,
      maxAge: maxAge == _sentinel ? this.maxAge : maxAge as int?,
      vibe: vibe == _sentinel ? this.vibe : vibe as String?,
      intent: intent == _sentinel ? this.intent : intent as String?,
      intents: intents == _sentinel
          ? this.intents
          : List<String>.unmodifiable(intents as List<String>),
    );
  }

  Map<String, String> toQueryParameters() {
    final q = <String, String>{};
    final selectedIntents = effectiveIntents;
    if (gender != null) q['gender'] = gender!;
    if (minAge != null) q['minAge'] = '$minAge';
    if (maxAge != null) q['maxAge'] = '$maxAge';
    if (vibe != null && vibe!.isNotEmpty) q['vibe'] = vibe!;
    if (selectedIntents.isNotEmpty) {
      q['intents'] = selectedIntents.join(',');
      if (selectedIntents.length == 1) {
        q['intent'] = selectedIntents.first;
      }
    }
    return q;
  }

  @override
  bool operator ==(Object other) =>
      other is AttendeeFilter &&
      other.gender == gender &&
      other.minAge == minAge &&
      other.maxAge == maxAge &&
      other.vibe == vibe &&
      listEquals(other.effectiveIntents, effectiveIntents);

  @override
  int get hashCode =>
      Object.hashAll([gender, minAge, maxAge, vibe, ...effectiveIntents]);
}

const Object _sentinel = Object();
