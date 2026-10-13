import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/checkin/services/personal_avatar_selection.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';

void main() {
  final active = ActiveCheckinService();
  const original = 'https://media.invalid/moments/a.jpg';
  const selected = 'https://media.invalid/moments/b.jpg';
  const crop = 'https://media.invalid/checkin-avatars/new.jpg';
  Map<String, dynamic> me({
    String? photo,
    String? featured = original,
    String? avatar = 'https://media.invalid/checkin-avatars/old.jpg',
    String user = 'owner',
  }) => {
    'id': user,
    'photo': photo,
    'activeCheckin': {
      'id': 'checkin',
      'avatarPhoto': avatar,
      'featuredPhoto': featured,
    },
  };
  setUp(() {
    active.clear();
    active.setActiveCheckin('checkin', userId: 'owner');
  });
  tearDown(active.clear);
  void star() => active.featuredPhotoChanged(
    checkinId: 'checkin',
    mediaId: 'photo-b',
    url: selected,
  );

  test(
    'server-confirmed star replaces previous crop without another request',
    () {
      final before = ActiveCheckinService.avatarChanges.value;
      star();
      final selection = PersonalAvatarSelection.fromMe(me());
      expect(selection.url, selected);
      expect(selection.reference, isNull);
      expect(ActiveCheckinService.avatarChanges.value, before + 1);
    },
  );
  test('a slow pre-star server response cannot restore the previous crop', () {
    star();
    expect(PersonalAvatarSelection.fromMe(me()).url, selected);
    expect(
      PersonalAvatarSelection.fromMe(
        me(featured: '$selected?signature=2', avatar: crop),
      ).url,
      crop,
    );
    expect(PersonalAvatarSelection.fromMe(me()).url, selected);
  });
  test(
    'permanent profile photo keeps precedence over a starred/cropped Moment',
    () {
      star();
      final selection = PersonalAvatarSelection.fromMe(me(photo: original));
      expect(selection.url, original);
      expect(selection.hasProfilePhoto, isTrue);
      expect(selection.reference, isNotNull);
    },
  );
  test(
    'null profile fields do not attach a profile reference to a check-in crop',
    () {
      final input = me(photo: 'null', featured: selected, avatar: crop);
      input['photo_temporary_url'] = original;
      final selection = PersonalAvatarSelection.fromMe(input);
      expect(selection.url, crop);
      expect(selection.reference, isNull);
    },
  );
  test('avatar fallback tolerates null strings and snake-case payloads', () {
    final selection = PersonalAvatarSelection.fromMe({
      'id': 'owner',
      'photo': ' ',
      'profile_photo': 'null',
      'active_checkin': {
        'id': 'checkin',
        'avatar_photo': 'null',
        'featured_photo': selected,
      },
    });
    expect(selection.url, selected);
  });
  test('featured override does not leak to another user or check-in', () {
    star();
    expect(
      PersonalAvatarSelection.fromMe(me(user: 'other')).url,
      contains('old.jpg'),
    );
    active.setActiveCheckin('different', userId: 'owner');
    expect(active.featuredMediaId, isNull);
    expect(PersonalAvatarSelection.fromMe(me()).url, contains('old.jpg'));
  });
  test('check-out removes the featured override', () {
    star();
    active.clear();
    expect(active.featuredMediaId, isNull);
    expect(PersonalAvatarSelection.fromMe({'id': 'owner'}).url, isNull);
  });
  test(
    'star reuses the loaded Moment cache, but never for a different crop',
    () {
      final reference = MediaReference(mediaId: 'photo-b:media', url: selected);
      active.featuredPhotoChanged(
        checkinId: 'checkin',
        mediaId: 'photo-b',
        url: selected,
        reference: reference,
      );
      expect(PersonalAvatarSelection.fromMe(me()).reference, same(reference));
      expect(
        PersonalAvatarSelection.fromMe(
          me(featured: selected, avatar: crop),
        ).reference,
        isNull,
      );
    },
  );
}
