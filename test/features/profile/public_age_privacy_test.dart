import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/models/public_age.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/people/data/username_search_item_model.dart';
import 'package:kmstry_frontend/features/people/data/suggested_person_item_model.dart';

void main() {
  test('public profile, check-in, search and suggestions accept age-only payloads', () {
    final json = <String, dynamic>{'id': 'other', 'age': 27};
    expect(PublicUserProfile.fromJson(json).age, 27);
    expect(CheckinProfileUser.fromJson(json).age, 27);
    expect(UsernameSearchItem.fromJson(json).age, 27);
    expect(SuggestedPersonItem.fromJson(json).age, 27);
  });
  test('legacy birthdays are ignored, never replaced by 1970 or persisted', () {
    final json = <String, dynamic>{'id': 'other', 'birthdate': '1990-01-01'};
    expect(PublicUserProfile.fromJson(json).age, isNull);
    expect(CheckinProfileUser.fromJson(json).age, isNull);
    expect(UsernameSearchItem.fromJson(json).age, isNull);
    expect(SuggestedPersonItem.fromJson(json).age, isNull);
  });
  test('unknown and malformed ages stay unknown', () {
    for (final value in [null, 'bad', -1, 1.5, double.infinity]) {
      expect(readPublicAge({'age': value}), isNull);
    }
  });
}
