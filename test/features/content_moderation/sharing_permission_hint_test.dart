import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/edit_profile_page.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/sharing_permission_hint.dart';

ApiException declined() => ApiException(
  statusCode: 403,
  data: const {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
);

class _Auth extends AuthRepository {
  final saves = <Map<String, dynamic>>[];
  @override
  Future<void> upsertPersonalProfile(Map<String, dynamic> data) async {
    saves.add(data);
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => PublicContentPermission.onRequired = null);

  test(
    'only an explicit Not now is cancellation; network/policy errors still fail',
    () async {
      for (final code in [
        'AWS_SHARING_PERMISSION_REQUIRED',
        'AWS_SHARING_NOTICE_CHANGED',
        'PUBLIC_TEXT_NOT_ALLOWED',
      ]) {
        final failure = ApiException(
          statusCode: 403,
          data: {'errorCode': code},
        );
        final controller = SharingPermissionController(
          ensure: () async => throw failure,
        );
        await expectLater(controller.check(), throwsA(same(failure)));
        expect(controller.deferred, false);
        controller.dispose();
      }
    },
  );

  test(
    'closing an editor during permission never resumes its submission',
    () async {
      final ready = Completer<void>();
      final controller = SharingPermissionController(
        ensure: () => ready.future,
      );
      final pending = controller.check();
      controller.dispose();
      ready.complete();
      expect(await pending, false);
    },
  );

  testWidgets(
    'personal Not now preserves bio, clears loading, and Review permission resumes save',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      var allow = false;
      var prompts = 0;
      PublicContentPermission.onRequired = (_) async {
        prompts++;
        if (!allow) throw declined();
      };
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfilePage(
            user: const {
              'fullName': 'Handan',
              'username': 'handan497',
              'bio': 'Original bio',
            },
            authRepository: auth,
          ),
        ),
      );
      final bio = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Original bio',
      );
      await tester.enterText(bio, 'My unsaved bio');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(auth.saves, isEmpty);
      expect(find.text('My unsaved bio'), findsOneWidget);
      expect(find.text('Could not save. Please try again.'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Review permission'), findsOneWidget);
      allow = true;
      await tester.tap(find.text('Review permission'));
      await tester.pumpAndSettle();
      expect(prompts, 2);
      expect(auth.saves.single['bio'], 'My unsaved bio');
      expect(tester.takeException(), isNull);
    },
  );
}
