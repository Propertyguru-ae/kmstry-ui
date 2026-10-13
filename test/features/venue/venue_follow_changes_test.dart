import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';

class _Api extends ApiClient {
  final started = Completer<void>();
  late Future<dynamic> Function() write;
  String? method;
  String? path;
  Map<String, String>? headers;

  Future<dynamic> _write(String verb, String url, Map<String, String>? auth) {
    method = verb;
    path = url;
    headers = auth;
    if (!started.isCompleted) started.complete();
    return write();
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => _write('POST', path, headers);

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _write('DELETE', path, headers);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-user'});
    PendingPublicMediaService.instance.clear();
    VenueContextRepository.followChanges.value = null;
  });
  tearDown(() {
    PendingPublicMediaService.instance.clear();
    VenueContextRepository.followChanges.value = null;
  });

  for (final following in [true, false]) {
    final verb = following ? 'follow' : 'unfollow';
    Future<dynamic> mutate(VenueContextRepository repo) =>
        following ? repo.followVenue('alpha') : repo.unfollowVenue('alpha');
    Map<String, dynamic> success() => {
      'ok': true,
      'isFollowing': following,
      'followerCount': 7,
    };

    test(
      '$verb notifies only after an authenticated successful write',
      () async {
        final response = Completer<dynamic>();
        final api = _Api()..write = () => response.future;
        final request = mutate(VenueContextRepository(apiClient: api));
        await api.started.future;
        expect(VenueContextRepository.followChanges.value, isNull);
        response.complete(success());
        expect(await request, success());
        final change = VenueContextRepository.followChanges.value!;
        expect(change.venueId, 'alpha');
        expect(change.following, following);
        expect(
          change.session,
          PendingPublicMediaService.instance.sessionGeneration,
        );
        expect(api.method, following ? 'POST' : 'DELETE');
        expect(api.path, '/venues/alpha/follow');
        expect(api.headers?['Authorization'], 'Bearer test-user');
      },
    );

    test(
      '$verb never notifies on a failed or contradictory response',
      () async {
        for (final invalid in [
          {'ok': false, 'isFollowing': following},
          {'ok': true, 'isFollowing': !following},
          <String, dynamic>{},
        ]) {
          final api = _Api()..write = () async => invalid;
          await expectLater(
            mutate(VenueContextRepository(apiClient: api)),
            throwsStateError,
          );
          expect(VenueContextRepository.followChanges.value, isNull);
        }
        final api = _Api()..write = () async => throw StateError('offline');
        await expectLater(
          mutate(VenueContextRepository(apiClient: api)),
          throwsStateError,
        );
        expect(VenueContextRepository.followChanges.value, isNull);
      },
    );

    test('$verb cannot notify another login after a late response', () async {
      final response = Completer<dynamic>();
      final api = _Api()..write = () => response.future;
      final request = mutate(VenueContextRepository(apiClient: api));
      await api.started.future;
      PendingPublicMediaService.instance.clear();
      response.complete(success());
      await request;
      expect(VenueContextRepository.followChanges.value, isNull);
    });

    test(
      '$verb stops if the login changes while credentials are read',
      () async {
        final api = _Api()..write = () async => success();
        final request = mutate(VenueContextRepository(apiClient: api));
        PendingPublicMediaService.instance.clear();
        await expectLater(request, throwsStateError);
        expect(api.started.isCompleted, false);
        expect(VenueContextRepository.followChanges.value, isNull);
      },
    );

    test('$verb is not dispatched without an access token', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = _Api()..write = () async => success();
      await expectLater(
        mutate(VenueContextRepository(apiClient: api)),
        throwsException,
      );
      expect(api.started.isCompleted, false);
      expect(VenueContextRepository.followChanges.value, isNull);
    });
  }
}
