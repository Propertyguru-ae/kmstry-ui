import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_gate_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_brand.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in <Size>[Size(320, 568), Size(393, 852), Size(430, 932)]) {
    testWidgets('brand stays aligned with native splash at $size', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues(const <String, String>{});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: StartupGatePage()));
      final firstRect = tester.getRect(find.byKey(StartupBrand.imageKey));
      expect(firstRect.size, StartupBrand.size);
      expect(firstRect.center.dx, size.width / 2);
      expect(firstRect.center.dy, size.height / 2 - StartupBrand.lift);
      expect(
        find.text('KMSTRY'),
        findsNothing,
      ); // No second, platform-specific font.
      expect(
        tester.widget<Image>(find.byKey(StartupBrand.imageKey)).semanticLabel,
        'KMSTRY',
      );
      final background = find.byKey(
        const ValueKey('startup-background-reveal'),
      );
      final tagline = find.byKey(const ValueKey('startup-tagline-reveal'));
      final footer = find.byKey(const ValueKey('startup-footer-reveal'));
      for (final reveal in [background, tagline, footer]) {
        expect(tester.widget<FadeTransition>(reveal).opacity.value, 0);
      }
      for (final duration in [
        Duration(milliseconds: 175),
        Duration(milliseconds: 175),
        Duration(seconds: 2),
      ]) {
        await tester.pump(duration);
        expect(tester.getRect(find.byKey(StartupBrand.imageKey)), firstRect);
        expect(
          tester.getCenter(find.text('REAL PLACES. REAL FACES.')).dx,
          closeTo(size.width / 2, 4),
        );
        expect(tester.takeException(), isNull);
      }
      for (final reveal in [background, tagline, footer]) {
        expect(tester.widget<FadeTransition>(reveal).opacity.value, 1);
      }
      final taglineRect = tester.getRect(find.text('REAL PLACES. REAL FACES.'));
      expect(taglineRect.bottom, lessThan(tester.getRect(footer).top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
