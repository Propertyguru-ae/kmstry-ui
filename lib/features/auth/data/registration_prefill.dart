import '../../../core/storage/secure_storage.dart';
import 'me_context_model.dart';

/// In-memory form defaults from the signed-in account, not a public profile or
/// an authorization cache. Never reuse them after logout or another login.
class RegistrationPrefill {
  const RegistrationPrefill._({
    required this.sessionRevision,
    this.name,
    this.birthdate,
    this.venueId,
  });

  final int sessionRevision;
  final String? name;
  final DateTime? birthdate;
  final String? venueId;

  bool get isCurrentSession => sessionRevision == SecureStorage.sessionRevision;

  factory RegistrationPrefill.fromMe(
    Map<String, dynamic> me, {
    required int sessionRevision,
  }) {
    String? name;
    for (final value in [
      me['fullName'],
      me['full_name'],
      me['registrationName'],
    ]) {
      final candidate = value?.toString().trim();
      if (candidate != null && candidate.isNotEmpty) {
        name = candidate;
        break;
      }
    }
    final rawDate = me['birthdate']?.toString().trim();
    final account = MeContextModel.fromMe(me);
    final venues = account.memberVenues.where((v) => v.isActive).toList();
    return RegistrationPrefill._(
      sessionRevision: sessionRevision,
      name: name,
      // A date of birth is a calendar date; do not shift it by local timezone.
      birthdate: rawDate == null || rawDate.isEmpty
          ? null
          : DateTime.tryParse(rawDate.split('T').first),
      venueId: venues.any((v) => v.id == account.activeVenueId)
          ? account.activeVenueId
          : venues.firstOrNull?.id,
    );
  }
}
