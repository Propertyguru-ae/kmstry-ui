import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/account_exists_sheet.dart';
import '../../support/theme_screens.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (_) async => 0,
        );
  });

  for (final name in ['signup-personal', 'personal-nameDob', 'venue-step-2']) {
    testWidgets('$name preserves entered details across system theme changes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: themePreviewScreens()[name]!(),
        ),
      );
      await tester.pumpAndSettle();
      final editable = find
          .byWidgetPredicate(
            (widget) => widget is EditableText && !widget.readOnly,
          )
          .first;
      expect(editable, findsOneWidget);
      await tester.enterText(editable, 'Saved local draft');
      final before = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((field) => field.controller.text)
          .toList();
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(editable)).brightness, brightness);
        expect(
          tester
              .widgetList<EditableText>(find.byType(EditableText))
              .map((field) => field.controller.text)
              .toList(),
          before,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('all intro slides respect ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          home: themePreviewScreens()['intro']!(),
        ),
      );
      await tester.pumpAndSettle();
      for (var slide = 0; slide < 3; slide++) {
        expect(
          Theme.of(tester.element(find.byType(PageView))).brightness,
          brightness,
        );
        expect(tester.takeException(), isNull);
        if (slide < 2) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Get Started'), findsOneWidget);
    });
    for (final entry in themePreviewScreens().entries) {
      testWidgets('${entry.key} respects ${brightness.name} appearance', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.darkTheme
                : AppTheme.lightTheme,
            home: entry.value(),
          ),
        );
        await tester.pumpAndSettle();
        final scaffold = find.byType(Scaffold).last;
        final theme = Theme.of(tester.element(scaffold));
        expect(theme.brightness, brightness);
        final color =
            tester.widget<Scaffold>(scaffold).backgroundColor ??
            theme.scaffoldBackgroundColor;
        expect(
          color.computeLuminance(),
          brightness == Brightness.dark ? lessThan(0.1) : greaterThan(0.8),
        );
        expect(tester.takeException(), isNull);
        // Dispose OTP cooldowns and nested onboarding routes before teardown.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }

    testWidgets('existing-account sheet follows ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAccountExistsSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('You already have an account')),
        ).brightness,
        brightness,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
