import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/media/overlay_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every bundled overlay font family is registered with its asset',
    () async {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      final families = {
        for (final entry in manifest.cast<Map<String, dynamic>>())
          entry['family'] as String: entry['fonts'] as List,
      };

      for (final font in OverlayFont.values) {
        final family = font.base(Colors.white).fontFamily;
        if (family == null) continue; // modern = sistem fontu
        expect(
          families,
          contains(family),
          reason: '${font.name} not in pubspec',
        );
        for (final asset in families[family]!) {
          final path = (asset as Map)['asset'] as String;
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(10000), reason: path);
        }
      }
    },
  );

  test('wire names round-trip and unknown values fall back to modern', () {
    for (final font in OverlayFont.values) {
      expect(overlayFontFromWire(font.wireName), font);
    }
    // Eski içerikler: bu değerler sunucuda kayıtlı, değişmemeli.
    expect(OverlayFont.classic.wireName, 'classic');
    expect(OverlayFont.typewriter.wireName, 'typewriter');
    expect(overlayFontFromWire(null), OverlayFont.modern);
    expect(overlayFontFromWire('future-font'), OverlayFont.modern);
  });

  test('viewer renders stored overlays with the shared font set', () {
    const overlay = MediaTextOverlay(
      text: 'Merhaba',
      colorValue: 0xFFFFFFFF,
      fontSizeNorm: 0.08,
      fontStyle: 'script',
    );
    expect(overlay.styleFor(400).fontFamily, 'Caveat');
  });

  test('OFL licenses are registered for every bundled font', () async {
    registerOverlayFontLicenses();
    final packages = <String>{};
    await for (final license in LicenseRegistry.licenses) {
      packages.addAll(license.packages);
    }
    expect(
      packages,
      containsAll([
        'Playfair Display',
        'Courier Prime',
        'Bebas Neue',
        'Caveat',
      ]),
    );
  });
}
