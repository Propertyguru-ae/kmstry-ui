import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping an empty area of New Event closes the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddVenueEventPage(venueId: 'v1')),
    );
    await tester.pump();
    final title = find.byType(TextField).first;
    await tester.tap(title);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);

    // Empty page margin left of the title field (no widget of its own).
    final field = tester.getCenter(title);
    await tester.tapAt(Offset(6, field.dy));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
