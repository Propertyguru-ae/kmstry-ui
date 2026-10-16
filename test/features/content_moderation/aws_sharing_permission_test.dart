import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/core/network/request_session.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/content_moderation/data/aws_sharing_permission.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/aws_sharing_permission_dialog.dart';

String token(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'version': 1})))}.signature';
const notice = <String, dynamic>{
  'version': '2026-10-15.1',
  'hash': 'notice-hash',
  'title': 'Safety checks for your public content',
  'paragraphs': [
    'KMSTRY sends public photos and text to Amazon Web Services (AWS) to check for harmful content. Photos and text may contain personal information.',
    'This permission applies to your personal and venue activity on this account, not to other team members. It is separate from device permissions and accepting the Terms.',
    'You can choose Not now and still use functions that do not need these checks, including account management and deletion. Change your choice in Settings → Privacy choices.',
  ],
  'acceptLabel': 'Allow safety checks',
  'declineLabel': 'Not now',
};

class PermissionApi extends ApiClient {
  bool granted = false;
  int reads = 0;
  final writes = <Map<String, dynamic>>[];
  final owners = <String?>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    reads++;
    return {'granted': granted, 'notice': notice, 'revision': 'revision-1'};
  }

  @override
  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    writes.add(body!);
    owners.add(headers?['Authorization']);
    granted = body['granted'] == true;
    return {'granted': granted, 'notice': notice};
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': token('owner')});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    PublicContentPermission.onRequired = null;
  });

  test(
    'one permission covers personal and venue uploads without repeated popups',
    () async {
      final api = PermissionApi();
      var prompts = 0;
      final service = AwsSharingPermission(
        api: api,
        prompt: (_) async {
          prompts++;
          return true;
        },
      );
      PublicContentPermission.onRequired = service.ensure;
      final headers = {'Authorization': 'Bearer ${token('owner')}'};
      for (final path in [
        '/checkins/c/stories',
        '/venues/v/venue-stories',
        '/venues/v/gallery',
        '/users/me/photo',
        '/venues/v/events/e/photos',
      ]) {
        await PublicContentPermission.beforeRequest('POST', path, headers);
      }
      expect(prompts, 1);
      expect(api.reads, 1);
      expect(api.writes.length, 1);
      expect(api.writes.single, {
        'granted': true,
        'noticeVersion': notice['version'],
        'noticeHash': notice['hash'],
        'expectedRevision': 'revision-1',
      });
    },
  );

  test('restarting restores a stored grant without a popup', () async {
    final api = PermissionApi()..granted = true;
    var prompts = 0;
    final service = AwsSharingPermission(
      api: api,
      prompt: (_) async {
        prompts++;
        return false;
      },
    );
    await service.ensure({'Authorization': 'Bearer ${token('owner')}'});
    expect(prompts, 0);
    expect(api.writes, isEmpty);
  });

  test('concurrent personal and venue submits share a single dialog', () async {
    final api = PermissionApi();
    final choice = Completer<bool>();
    var prompts = 0;
    final service = AwsSharingPermission(
      api: api,
      prompt: (_) {
        prompts++;
        return choice.future;
      },
    );
    final headers = {'Authorization': 'Bearer ${token('owner')}'};
    final one = service.ensure(headers);
    final two = service.ensure(headers);
    await flush();
    expect(prompts, 1);
    choice.complete(true);
    await Future.wait([one, two]);
    expect(api.writes.length, 1);
  });

  test(
    'Not now immediately defers without a write or a delayed withdrawal',
    () async {
      final api = PermissionApi();
      var sends = 0;
      final service = AwsSharingPermission(
        api: api,
        prompt: (_) async => false,
      );
      Future<void> submit() async {
        await service.ensure({'Authorization': 'Bearer ${token('owner')}'});
        sends++;
      }

      await expectLater(
        submit(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.data['errorCode'],
            'code',
            'AWS_SHARING_PERMISSION_DECLINED',
          ),
        ),
      );
      expect(sends, 0);
      expect(api.granted, false);
      expect(api.writes, isEmpty);
    },
  );

  test(
    'logout/account switch while dialog is open never grants the next account',
    () async {
      final api = PermissionApi();
      final choice = Completer<bool>();
      final service = AwsSharingPermission(
        api: api,
        prompt: (_) => choice.future,
      );
      final waiting = service.ensure({
        'Authorization': 'Bearer ${token('owner')}',
      });
      final assertion = expectLater(
        waiting,
        throwsA(isA<RequestSessionChanged>()),
      );
      await flush();
      await SecureStorage.saveTokens(
        accessToken: token('teammate'),
        refreshToken: 'test-refresh',
      );
      choice.complete(true);
      await assertion;
      expect(api.writes, isEmpty);
      service.prompt = (_) async => true;
      await service.ensure({'Authorization': 'Bearer ${token('teammate')}'});
      expect(api.owners.single, 'Bearer ${token('teammate')}');
    },
  );

  test('withdrawal and stale notice invalidate the memory hint', () async {
    final api = PermissionApi();
    var prompts = 0;
    final service = AwsSharingPermission(
      api: api,
      prompt: (_) async {
        prompts++;
        return true;
      },
    );
    final headers = {'Authorization': 'Bearer ${token('owner')}'};
    await service.ensure(headers);
    await service.withdraw();
    expect(api.granted, false);
    await service.ensure(headers);
    expect(prompts, 2);
    service.invalidate();
    api.granted = false;
    await service.ensure(headers);
    expect(prompts, 3);
  });

  test(
    'login, reads, private documents, reports and deletion do not ask for AWS',
    () {
      for (final path in [
        '/auth/login',
        '/messages/m/media',
        '/reports',
        '/venues/claim/documents',
        '/venues/claim-draft/upload',
        '/venues/ensure-from-place',
        '/privacy/aws-sharing-permission',
      ]) {
        expect(
          PublicContentPermission.requiresPermission('POST', path, {}),
          false,
          reason: path,
        );
      }
      expect(
        PublicContentPermission.requiresPermission(
          'PUT',
          '/venues/claim-draft',
          {'ownerNote': 'private'},
        ),
        false,
      );
      expect(
        PublicContentPermission.requiresPermission('DELETE', '/users/me', {}),
        false,
      );
      expect(
        PublicContentPermission.requiresPermission(
          'GET',
          '/venues/v/gallery',
          {},
        ),
        false,
      );
      expect(
        PublicContentPermission.requiresPermission('PATCH', '/users/me', {
          'optionalAnalyticsEnabled': false,
        }),
        false,
      );
      expect(
        PublicContentPermission.requiresPermission('PATCH', '/users/me', {
          'bio': 'Hello',
        }),
        true,
      );
      expect(
        PublicContentPermission.requiresPermission('PATCH', '/venues/v', {
          'description': 'Hello',
        }),
        true,
      );
    },
  );

  for (final kind in PendingPublicMediaKind.values) {
    test(
      'permission decline removes local ${kind.name} draft instead of a false network error',
      () async {
        final service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) async => const MediaModerationSnapshot(),
          delay: (_) => Completer<void>().future,
        );
        final draft = PendingPublicMedia(
          id: 'draft',
          kind: kind,
          venueId: 'venue',
          localPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
          hasServerReceipt: false,
        );
        await expectLater(
          service.runTrackedUpload<Map<String, dynamic>>(
            draft: draft,
            expectedGeneration: service.sessionGeneration,
            send: (_) async => throw ApiException(
              statusCode: 403,
              data: {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
            ),
            receiptId: (_) => 'receipt',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(service.byId('draft'), isNull);
        service.clear();
      },
    );
  }

  testWidgets(
    'notice scrolls on a small screen with large text and offers both choices',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      choice = await showAwsSharingPermissionDialog(
                        context,
                        notice,
                      );
                    },
                    child: const Text('Share'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // App-standard solid blue CTA, kept on screen while the notice scrolls.
      expect(
        find.widgetWithText(PrimaryButton, 'Allow safety checks'),
        findsOneWidget,
      );
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getBottomLeft(find.text('Not now')).dy,
        lessThanOrEqualTo(screen.height),
      );
      await tester.drag(
        find.text(notice['paragraphs'][0] as String),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(notice['paragraphs'][2] as String).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(choice, false);
      expect(tester.takeException(), isNull);
    },
  );
}
