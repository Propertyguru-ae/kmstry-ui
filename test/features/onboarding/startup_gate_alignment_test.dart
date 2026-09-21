import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_gate_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in <double>[320, 393, 430]) {
    testWidgets('startup title and slogan are centered at ${width.toInt()}pt', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues(const <String, String>{});
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: StartupGatePage()));
      await tester.pump(const Duration(milliseconds: 1100));

      for (final label in <String>['KMSTRY', 'REAL PLACES. REAL FACES.']) {
        final center = tester.getCenter(find.text(label));
        expect(center.dx, closeTo(width / 2, 4));
        expect(tester.getSize(find.text(label)).height, lessThan(60));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
