import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// The server answers 404 for a banned (or deleted) account.
class GoneProfile extends CheckinRepository {
  @override
  Future<PublicUserProfile> getPublicUserProfile(String userId) async =>
      throw ApiException(
        statusCode: 404,
        data: {'message': 'Profile not found'},
      );

  @override
  Future<Set<String>> getBlockedUserIds() async => <String>{};
}

void main() {
  testWidgets(
    'a banned friend opened from a list shows "Profile unavailable", not their name or photo',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ProfilePreviewPage(
            userId: 'mehmet',
            userName: 'Mehmet Krkc',
            userUsername: 'mehmetkrkc',
            isMatchedHint: true,
            checkinRepository: GoneProfile(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile unavailable'), findsOneWidget);
      expect(find.text('This account isn\'t available right now.'), findsOneWidget);
      expect(find.text('Mehmet Krkc'), findsNothing);
      expect(find.text('@mehmetkrkc'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
