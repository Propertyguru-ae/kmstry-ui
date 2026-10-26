import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/theme/appearance_system_ui.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/core/theme/widgets/theme_toggle_button.dart';
import 'package:provider/provider.dart';

void main() {
  for (final saved in <String?>[
    null,
    'system',
    'auto',
    'invalid',
    'light',
    'dark',
  ]) {
    test(
      'restores $saved, defaults to Auto without rewriting storage',
      () async {
        final writes = <String>[];
        final provider = ThemeProvider(
          readPreference: () async => saved,
          writePreference: (value) async => writes.add(value),
        );
        addTearDown(provider.dispose);
        await provider.ready;
        expect(provider.themeMode, switch (saved) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        });
        expect(writes, isEmpty);
      },
    );
  }

  test('late restore never overrides a user selection', () async {
    final read = Completer<String?>();
    final provider = ThemeProvider(
      readPreference: () => read.future,
      writePreference: (_) async {},
    );
    addTearDown(provider.dispose);
    await provider.setThemeMode(ThemeMode.light);
    read.complete('dark');
    await provider.ready;
    expect(provider.themeMode, ThemeMode.light);
  });

  test('rapid choices persist in order and survive relaunch', () async {
    String? saved;
    final firstWrite = Completer<void>();
    final writes = <String>[];
    final provider = ThemeProvider(
      readPreference: () async => saved,
      writePreference: (value) async {
        if (value == 'dark') await firstWrite.future;
        saved = value;
        writes.add(value);
      },
    );
    addTearDown(provider.dispose);
    await provider.ready;
    final dark = provider.setThemeMode(ThemeMode.dark);
    final light = provider.setThemeMode(ThemeMode.light);
    final auto = provider.setThemeMode(ThemeMode.system);
    expect(provider.themeMode, ThemeMode.system);
    firstWrite.complete();
    await Future.wait([dark, light, auto]);
    expect(writes, ['dark', 'light', 'system']);
    final relaunched = ThemeProvider(
      readPreference: () async => saved,
      writePreference: (_) async {},
    );
    addTearDown(relaunched.dispose);
    await relaunched.ready;
    expect(relaunched.themeMode, ThemeMode.system);
  });

  test('unavailable storage does not prevent startup', () async {
    final provider = ThemeProvider(
      readPreference: () async => throw StateError('unavailable'),
      writePreference: (_) async {},
    );
    addTearDown(provider.dispose);
    await provider.ready;
    expect(provider.themeMode, ThemeMode.system);
  });

  testWidgets('Auto follows system; manual modes ignore it; form survives', (
    tester,
  ) async {
    final provider = ThemeProvider(
      readPreference: () async => null,
      writePreference: (_) async {},
    );
    addTearDown(provider.dispose);
    await provider.ready;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: Consumer<ThemeProvider>(
          builder: (_, theme, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            builder: (_, child) => AppearanceSystemUi(child: child!),
            home: const Scaffold(
              body: Column(children: [TextField(), ThemeToggleButton()]),
            ),
          ),
        ),
      ),
    );
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(TextField))).brightness;
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    expect(brightness(), Brightness.light);
    expect(
      tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
          )
          .value
          .statusBarIconBrightness,
      Brightness.dark,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    expect(
      tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
          )
          .value
          .statusBarIconBrightness,
      Brightness.light,
    );
    expect(find.text('Unsaved draft'), findsOneWidget);
    await provider.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await provider.setThemeMode(ThemeMode.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(find.text('Unsaved draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
