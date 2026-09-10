import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';

class ControlledApi extends ApiClient {
  final gets = <Completer<dynamic>>[];
  final posts = <Completer<dynamic>>[];
  final paths = <String>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) {
    paths.add(path);
    final result = Completer<dynamic>();
    gets.add(result);
    return result.future;
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    dynamic body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final result = Completer<dynamic>();
    posts.add(result);
    return result.future;
  }
}

Map<String, dynamic> msg(String id, int minute) => {
  'id': id,
  'message_type': 'image',
  'image_url': 'https://example.com/$id',
  'created_at': DateTime.utc(2026, 9, 9, 10, minute).toIso8601String(),
};
Map<String, dynamic> page(String id, int minute) => {
  'id': 'chat',
  'messages': [msg(id, minute)],
};

void main() {
  late ControlledApi api;
  late ChatMemoryCache cache;
  late ChatRepository repo;
  setUp(() {
    api = ControlledApi();
    cache = ChatMemoryCache();
    repo = ChatRepository(
      api: api,
      cache: cache,
      tokenProvider: () async => 'test-token',
    );
  });
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('older pagination page never replaces latest reopen snapshot', () async {
    final latest = repo.getChat('chat');
    await tick();
    api.gets.last.complete(page('latest', 5));
    await latest;
    final older = repo.getChat('chat', beforeId: 'latest', markRead: false);
    await tick();
    api.gets.last.complete(page('older', 1));
    expect((await older).messages.single.id, 'older');
    expect(repo.cachedChat('chat')!.messages.single.id, 'latest');
  });

  test(
    'send updates shared detail even without a mounted conversation',
    () async {
      final send = repo.sendMessage(
        'chat',
        messageType: 'image',
        imageUrl: 'https://example.com/photo',
      );
      await tick();
      api.posts.single.complete(msg('photo', 5));
      await send;
      final reopened = ChatRepository(
        api: api,
        cache: cache,
        tokenProvider: () async => 'test-token',
      );
      expect(reopened.cachedChat('chat')!.messages.single.id, 'photo');
    },
  );

  test(
    'prefetch started before send cannot overwrite its confirmation',
    () async {
      final prefetch = repo.getChat('chat', markRead: false);
      await tick();
      final send = repo.sendMessage('chat', messageType: 'text', text: 'hello');
      await tick();
      api.posts.single.complete(msg('new', 5));
      await send;
      api.gets.single.complete(page('old', 1));
      expect((await prefetch).messages.first.id, 'new');
      expect(repo.cachedChat('chat')!.messages.first.id, 'new');
    },
  );

  test(
    'late response after logout cannot repopulate cached private messages',
    () async {
      final request = repo.getChat('chat');
      await tick();
      cache.clear();
      api.gets.single.complete(page('old', 1));
      await request;
      expect(repo.cachedChat('chat'), isNull);
    },
  );

  test(
    'send confirmation after logout cannot repopulate another session',
    () async {
      final send = repo.sendMessage('chat', messageType: 'text', text: 'hello');
      await tick();
      cache.clear();
      api.posts.single.complete(msg('new', 5));
      await send;
      expect(repo.cachedChat('chat'), isNull);
    },
  );
}
