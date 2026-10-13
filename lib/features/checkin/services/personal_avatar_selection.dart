import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'active_checkin_service.dart';

/// One selection policy for the signed-in user's profile and navbar.
class PersonalAvatarSelection {
  const PersonalAvatarSelection({
    this.url,
    this.reference,
    this.checkinId,
    this.hasProfilePhoto = false,
  });
  final String? url;
  final MediaReference? reference;
  final String? checkinId;
  final bool hasProfilePhoto;

  static String? _photo(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text.toLowerCase() == 'null'
        ? null
        : text;
  }

  factory PersonalAvatarSelection.fromMe(
    Map<String, dynamic> me, {
    Map<String, dynamic>? activeCheckin,
    String? featuredFallback,
  }) {
    for (final key in const [
      'photo',
      'profilePhoto',
      'profile_photo',
      'avatarUrl',
      'avatar_url',
    ]) {
      final photo = _photo(me[key]);
      if (photo != null) {
        final reference = MediaReference.profilePhoto(me);
        return PersonalAvatarSelection(
          url: photo,
          hasProfilePhoto: true,
          reference: reference.url.isEmpty ? null : reference,
        );
      }
    }
    final raw = activeCheckin ?? me['activeCheckin'] ?? me['active_checkin'];
    if (raw is! Map) return const PersonalAvatarSelection();
    final id = _photo(raw['id']);
    final avatar = _photo(raw['avatarPhoto']) ?? _photo(raw['avatar_photo']);
    final featured =
        _photo(raw['featuredPhoto']) ??
        _photo(raw['featured_photo']) ??
        _photo(featuredFallback);
    final active = ActiveCheckinService();
    final url = active.resolveAvatar(
      checkinId: id,
      userId: me['id']?.toString(),
      avatarUrl: avatar,
      featuredUrl: featured,
    );
    return PersonalAvatarSelection(
      checkinId: id,
      url: url,
      reference: active.avatarReference(
        checkinId: id,
        userId: me['id']?.toString(),
        url: url,
      ),
    );
  }
}
