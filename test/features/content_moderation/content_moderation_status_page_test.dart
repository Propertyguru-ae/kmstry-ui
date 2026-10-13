import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_item.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/content_moderation_status_page.dart';

ContentModerationItem _item(String id) => ContentModerationItem(
  id: id,
  targetType: 'PERSONAL_STORY',
  targetId: 'story-$id',
  mediaType: 'IMAGE',
  status: 'REJECTED',
  createdAt: DateTime(2026, 10, 2),
  updatedAt: DateTime(2026, 10, 2),
  userMessage: 'Rejection reason $id',
);

class _Repository extends ContentModerationRepository {
  final calls = <({int page, int limit, int? recentDays})>[];
  bool failNextPage = false;
  Completer<ContentModerationPageResult>? delayedPage;

  @override
  Future<ContentModerationPageResult> listMyItems({
    int page = 1,
    int limit = 20,
    int? recentDays,
    String? status,
    String? targetType,
    String? targetId,
    String? itemId,
  }) async {
    calls.add((page: page, limit: limit, recentDays: recentDays));
    if (page == 2 && failNextPage) throw StateError('Offline');
    if (page == 2 && delayedPage != null) return delayedPage!.future;
    return ContentModerationPageResult(
      items: page == 1 ? [_item('one'), _item('two')] : [_item('three')],
      total: 3,
      page: page,
      limit: limit,
    );
  }
}

class _Api extends ApiClient {
  final queries = <Uri>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    queries.add(Uri.parse(path));
    return {'data': [], 'total': 0, 'page': 1, 'limit': 20};
  }
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(home: ContentModerationStatusPage(repository: repository)),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadMore(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Load more'));
  await tester.tap(find.text('Load more'));
  await tester.pump();
}

void main() {
  testWidgets('history uses server-side 30-day window and 20-item pages', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    expect(find.textContaining('last 30 days'), findsOneWidget);
    expect(repository.calls, [(page: 1, limit: 20, recentDays: 30)]);
    await _loadMore(tester);
    await tester.pumpAndSettle();
    expect(repository.calls, [
      (page: 1, limit: 20, recentDays: 30),
      (page: 2, limit: 20, recentDays: 30),
    ]);
    expect(find.text('Load more'), findsNothing);
    expect(find.text('Rejection reason three'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination failure retains reasons and supports retry', (
    tester,
  ) async {
    final repository = _Repository()..failNextPage = true;
    await _open(tester, repository);
    await _loadMore(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not load more. Please try again.'), findsOneWidget);
    expect(find.text('Rejection reason two'), findsOneWidget);
    expect(tester.takeException(), isNull);
    repository.failNextPage = false;
    await _loadMore(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not load more. Please try again.'), findsNothing);
    expect(find.text('Rejection reason three'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh ignores an older pagination response', (tester) async {
    final page = Completer<ContentModerationPageResult>();
    final repository = _Repository()..delayedPage = page;
    await _open(tester, repository);
    await _loadMore(tester);
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.map((c) => c.page), [1, 2, 1]);
    page.complete(
      ContentModerationPageResult(
        items: [_item('stale')],
        total: 3,
        page: 2,
        limit: 20,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rejection reason stale'), findsNothing);
    expect(find.text('Load more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'history query does not restrict exact moderation receipt polling',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
      final api = _Api();
      final repository = ContentModerationRepository(apiClient: api);
      await repository.listMyItems(page: 2, recentDays: 30);
      await repository.listMyItems(itemId: 'moderation-receipt');
      expect(api.queries.first.queryParameters, {
        'page': '2',
        'limit': '20',
        'recentDays': '30',
      });
      expect(api.queries.last.queryParameters['recentDays'], isNull);
      expect(api.queries.last.queryParameters['itemId'], 'moderation-receipt');
    },
  );
}
