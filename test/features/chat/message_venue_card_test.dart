import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
// Firebase's official platform-channel test adapter; no real project/network.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends ChatRepository {
  _Repo() : super(cache: ChatMemoryCache());
  @override
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) async => ChatDetail(
    id: 'chat',
    messages: [
      ChatMessage.fromJson({
        'id': 'message',
        'sender_id': 'other',
        'message_type': 'venue',
        'venue_id': 'venue-1',
        'venue': {
          'id': 'venue-1',
          'name': 'Test Cafe Alpha',
          'description': 'Specialty coffee and live music.',
          'latitude': 25.2,
          'longitude': 55.3,
        },
        'created_at': DateTime.now().toIso8601String(),
      }),
    ],
  );

  @override
  Future<void> markChatRead(String chatId) async {}
}

class _Venues extends VenueContextRepository {
  _Venues(this.read);
  final Future<VenuePhone> Function() read;
  final venueIds = <String?>[];

  @override
  Future<VenuePhone> getVenuePhone({String? venueId, String? placeId}) {
    venueIds.add(venueId);
    return read();
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Venues venues, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  Future<bool> Function(Uri)? launcher,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MessageDetailPage(
        chatId: 'chat',
        otherUserId: 'other',
        otherName: 'Other User',
        otherPhotoUrl: '',
        repository: _Repo(),
        venueContextRepository: venues,
        phoneLinkLauncher: launcher,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Test Cafe Alpha'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(390, 844), const Size(320, 640)]) {
      testWidgets(
        'three actions share one row; dark=$dark width=${size.width}',
        (tester) async {
          final venues = _Venues(() async => const VenuePhone());
          await _pump(
            tester,
            venues,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            size: size,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('View details'), findsOneWidget);
          expect(find.text('Directions'), findsNothing);
          expect(find.text('Call'), findsNothing);
          final details = tester.getRect(
            find
                .ancestor(
                  of: find.text('View details'),
                  matching: find.byType(Material),
                )
                .first,
          );
          final directions = tester.getRect(find.byTooltip('Directions'));
          final call = tester.getRect(find.byTooltip('Call'));
          expect(details.height, directions.height);
          expect(details.height, call.height);
          expect(details.top, directions.top);
          expect(details.top, call.top);
          expect(details.right, lessThan(directions.left));
          expect(directions.right, lessThan(call.left));
          expect(find.byIcon(Icons.call_rounded), findsOneWidget);
          // Showing a card must not cost a phone lookup.
          expect(venues.venueIds, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('Call looks the number up on tap, then dials it', (tester) async {
    final pending = Completer<VenuePhone>();
    final venues = _Venues(() => pending.future);
    Uri? dialed;
    await _pump(
      tester,
      venues,
      launcher: (uri) async {
        dialed = uri;
        return true;
      },
    );
    await tester.tap(find.byTooltip('Call'));
    await tester.pump();
    expect(venues.venueIds, ['venue-1']);
    expect(find.byIcon(Icons.call_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(dialed, isNull);

    // A second tap while waiting starts no lookup and doesn't reach the card,
    // whose own tap opens the venue page.
    await tester.tap(find.byTooltip('Call'));
    await tester.pump();
    expect(venues.venueIds, ['venue-1']);
    expect(find.byType(VenueDetailPage), findsNothing);

    pending.complete(const VenuePhone(phone: '+442079460001'));
    await tester.pump();
    await tester.pump();
    expect(dialed.toString(), 'tel:+442079460001');
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final fails in [false, true]) {
    testWidgets('Call without a number explains why; error=$fails', (
      tester,
    ) async {
      final venues = _Venues(
        () async =>
            fails ? throw StateError('unavailable') : const VenuePhone(),
      );
      Uri? dialed;
      await _pump(
        tester,
        venues,
        launcher: (uri) async {
          dialed = uri;
          return true;
        },
      );
      await tester.tap(find.byTooltip('Call'));
      await tester.pump();
      await tester.pump();
      expect(dialed, isNull);
      expect(
        find.text(
          fails
              ? 'Could not get the phone number. Please try again.'
              : 'No phone number available for this venue.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
