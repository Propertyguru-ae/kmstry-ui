import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';

void main() {
  final active = ActiveCheckinService();
  const photo = 'https://media.invalid/checkins/selected.jpg';
  final reference = MediaReference(mediaId: 'moment:media', url: photo);

  setUp(active.clear);
  tearDown(active.clear);

  void selectAvatar() => active.featuredPhotoChanged(
    checkinId: 'checkin',
    mediaId: 'moment',
    url: photo,
    reference: reference,
  );

  for (final missing in ['user', 'venue', 'both']) {
    test('completing $missing keeps the room identity and selected avatar', () {
      active.setActiveCheckin(
        'checkin',
        userId: missing == 'venue' ? 'handan' : null,
        venueId: missing == 'user' ? 'beta' : null,
      );
      selectAvatar();
      final identity = active.identityRevision;
      final changes = ActiveCheckinService.changes.value;
      active.syncForUser(
        userId: 'handan',
        checkinId: 'checkin',
        venueId: 'beta',
      );
      expect(active.identityRevision, identity);
      expect(ActiveCheckinService.changes.value, changes + 1);
      expect(active.activeUserId, 'handan');
      expect(active.activeVenueId, 'beta');
      expect(active.featuredMediaId, 'moment');
      expect(
        active.avatarReference(
          checkinId: 'checkin',
          userId: 'handan',
          url: photo,
        ),
        same(reference),
      );
      expect(active.belongsToUser('another-user'), isFalse);
      active.syncForUser(
        userId: 'handan',
        checkinId: 'checkin',
        venueId: 'beta',
      );
      expect(active.identityRevision, identity);
      expect(ActiveCheckinService.changes.value, changes + 1);
    });
  }

  test('an incomplete same-check-in update cannot erase known ownership', () {
    active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
    selectAvatar();
    final identity = active.identityRevision;
    final changes = ActiveCheckinService.changes.value;
    active.setActiveCheckin('checkin');
    active.setActiveCheckin('checkin', userId: ' ', venueId: ' ');
    active.syncForUser(userId: 'handan', checkinId: 'checkin');
    expect(active.activeUserId, 'handan');
    expect(active.activeVenueId, 'beta');
    expect(active.belongsToUser('other'), isFalse);
    expect(active.identityRevision, identity);
    expect(ActiveCheckinService.changes.value, changes);
    expect(active.featuredMediaId, 'moment');
  });

  for (final change in ['user', 'venue', 'checkin']) {
    test(
      'a real $change change invalidates identity and the previous avatar',
      () {
        active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
        selectAvatar();
        final identity = active.identityRevision;
        final changes = ActiveCheckinService.changes.value;
        active.setActiveCheckin(
          change == 'checkin' ? 'new-checkin' : 'checkin',
          userId: change == 'user' ? 'other' : 'handan',
          venueId: change == 'venue' ? 'alpha' : 'beta',
        );
        expect(active.identityRevision, identity + 1);
        expect(ActiveCheckinService.changes.value, changes + 1);
        expect(active.featuredMediaId, isNull);
      },
    );
  }

  test('a new check-in does not inherit absent owner or venue fields', () {
    active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
    active.setActiveCheckin('new-checkin');
    expect(active.activeUserId, isNull);
    expect(active.activeVenueId, isNull);
  });

  test('a different owner cannot inherit an omitted venue', () {
    active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
    active.setActiveCheckin('checkin', userId: 'other');
    expect(active.activeUserId, 'other');
    expect(active.activeVenueId, isNull);
    expect(active.belongsToUser('handan'), isFalse);
  });

  test(
    'clearing and reusing the same IDs is a new identity, not enrichment',
    () {
      active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
      selectAvatar();
      final identity = active.identityRevision;
      active.clear();
      expect(active.identityRevision, identity + 1);
      expect(active.hasActiveCheckin, isFalse);
      expect(active.featuredMediaId, isNull);
      active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
      expect(active.identityRevision, identity + 2);
    },
  );

  for (final missing in ['user', 'checkin']) {
    test('authoritative sync without $missing still clears the check-in', () {
      active.setActiveCheckin('checkin', userId: 'handan', venueId: 'beta');
      final identity = active.identityRevision;
      active.syncForUser(
        userId: missing == 'user' ? null : 'handan',
        checkinId: missing == 'checkin' ? null : 'checkin',
      );
      expect(active.identityRevision, identity + 1);
      expect(active.hasActiveCheckin, isFalse);
      expect(active.activeUserId, isNull);
      expect(active.activeVenueId, isNull);
    });
  }
}
