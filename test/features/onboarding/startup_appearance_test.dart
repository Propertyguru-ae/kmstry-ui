import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_gate_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/startup_brand.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final initial in Brightness.values) {
    testWidgets('startup follows Auto from ${initial.name} without resetting', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.platformBrightnessTestValue = initial;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: const StartupGatePage(),
        ),
      );
      // Startup has deliberately repeating glow/pulse animations.
      await tester.pump(const Duration(milliseconds: 1100));
      final state = tester.state(find.byType(StartupGatePage));
      for (final appearance in [
        initial,
        initial == Brightness.light ? Brightness.dark : Brightness.light,
      ]) {
        tester.platformDispatcher.platformBrightnessTestValue = appearance;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final dark = appearance == Brightness.dark;
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          dark ? const Color(0xFF06091A) : const Color(0xFFF7FAFF),
        );
        expect(
          (tester.widget<Image>(find.byKey(StartupBrand.imageKey)).image
                  as AssetImage)
              .assetName,
          dark ? StartupBrand.darkAsset : StartupBrand.lightAsset,
        );
        expect(
          tester
              .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .value
              .statusBarIconBrightness,
          dark ? Brightness.light : Brightness.dark,
        );
        expect(tester.state(find.byType(StartupGatePage)), same(state));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  test('native launch resources retain dark and supply a light appearance', () {
    final colors =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/LaunchBackgroundColor.colorset/Contents.json',
              ).readAsStringSync(),
            )
            as Map;
    final entries = colors['colors'] as List;
    expect(entries[0]['color']['components'], containsPair('red', '0xF7'));
    expect(entries[1]['appearances'][0]['value'], 'dark');
    expect(entries[1]['color']['components'], containsPair('red', '0x06'));
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreenBrand.storyboard',
    ).readAsStringSync();
    expect(storyboard, contains('name="LaunchBackgroundColor"'));
    expect(storyboard, isNot(contains('image="LaunchBackground"')));
    expect(storyboard, contains('image="LaunchBrandAppearance"'));
    expect(storyboard, contains('constant="-64" id="duK-uY-Gun"'));
    expect(StartupBrand.lift, 32);
    expect(storyboard, isNot(contains('image="LaunchImage"')));
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      info,
      matches(
        RegExp(
          r'<key>UILaunchStoryboardName</key>\s*<string>LaunchScreenBrand</string>',
        ),
      ),
    );
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('Base.lproj/LaunchScreenBrand.storyboard'));
    expect(project, isNot(contains('Base.lproj/LaunchScreen.storyboard')));
    final launchImages =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/LaunchBrandAppearance.imageset/Contents.json',
              ).readAsStringSync(),
            )['images']
            as List;
    expect(launchImages.length, 6);
    for (final appearance in ['light', 'dark']) {
      final flutter = File('assets/images/startup_brand_$appearance.png');
      final native = File(
        'ios/Runner/Assets.xcassets/LaunchBrandAppearance.imageset/'
        '${appearance == 'dark' ? 'LaunchImageDark' : 'LaunchImage'}@3x.png',
      );
      expect(
        flutter.readAsBytesSync(),
        orderedEquals(native.readAsBytesSync()),
      );
    }
    for (final scale in ['1x', '2x', '3x']) {
      final variants = launchImages.where((entry) => entry['scale'] == scale);
      expect(variants.length, 2);
      expect(variants.where((entry) => entry['appearances'] == null).length, 1);
      final dark = variants.singleWhere(
        (entry) => entry['appearances'] != null,
      );
      expect(dark['appearances'][0]['value'], 'dark');
      for (final entry in variants) {
        expect(
          File(
            'ios/Runner/Assets.xcassets/LaunchBrandAppearance.imageset/'
            '${entry['filename']}',
          ).existsSync(),
          isTrue,
        );
      }
    }
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final appearance in ['', 'night-']) {
        expect(
          File(
            'android/app/src/main/res/'
            'drawable-$appearance$density/splash.png',
          ).existsSync(),
          isTrue,
        );
      }
    }
    final splashConfig = File('pubspec.yaml').readAsStringSync();
    expect(
      splashConfig,
      contains('image: assets/images/native_splash_logo_light.png'),
    );
    expect(
      splashConfig,
      contains('image_dark: assets/images/native_splash_logo_dark.png'),
    );
    expect(
      File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
      contains('name="launch_background_color">#F7FAFF'),
    );
    expect(
      File(
        'android/app/src/main/res/values-night/colors.xml',
      ).readAsStringSync(),
      contains('name="launch_background_color">#06091A'),
    );
    for (final file in [
      'drawable/launch_background.xml',
      'drawable-v21/launch_background.xml',
      'values-v31/styles.xml',
      'values-night-v31/styles.xml',
    ]) {
      expect(
        File('android/app/src/main/res/$file').readAsStringSync(),
        contains('@color/launch_background_color'),
      );
    }
  });
}
