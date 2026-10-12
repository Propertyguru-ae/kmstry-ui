import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Foto/video metin overlay'lerinin font seti — TEK kaynak.
///
/// Editörler (foto önizleme + video composer) ve izleyici tarafı
/// (MediaTextOverlay) buradan okur; yeni font eklemek = buraya bir değer.
/// Fontlar uygulamaya paketlidir (pubspec `fonts:`), her platformda aynı
/// görünür. `wireName` sunucuya/JSON'a yazılan değerdir — mevcut değerleri
/// DEĞİŞTİRMEYİN; eski içerikler ve eski uygulama sürümleri buna bağlı
/// (tanınmayan değer eski sürümlerde güvenle 'modern'e düşer).
enum OverlayFont { modern, classic, typewriter, bold, script }

extension OverlayFontX on OverlayFont {
  String get label => switch (this) {
    OverlayFont.modern => 'Modern',
    OverlayFont.classic => 'Classic',
    OverlayFont.typewriter => 'Typewriter',
    OverlayFont.bold => 'Bold',
    OverlayFont.script => 'Script',
  };

  String get wireName => switch (this) {
    OverlayFont.modern => 'modern',
    OverlayFont.classic => 'classic',
    OverlayFont.typewriter => 'typewriter',
    OverlayFont.bold => 'bold',
    OverlayFont.script => 'script',
  };

  /// Fontun temel stili (boyut çağıran tarafta verilir).
  TextStyle base(Color color) => switch (this) {
    OverlayFont.modern => TextStyle(
      color: color,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    ),
    OverlayFont.classic => TextStyle(
      color: color,
      fontFamily: 'Playfair Display',
      fontWeight: FontWeight.w700,
    ),
    OverlayFont.typewriter => TextStyle(
      color: color,
      fontFamily: 'Courier Prime',
      fontWeight: FontWeight.w700,
    ),
    OverlayFont.bold => TextStyle(
      color: color,
      fontFamily: 'Bebas Neue',
      fontWeight: FontWeight.w400,
      letterSpacing: 1.0,
    ),
    OverlayFont.script => TextStyle(
      color: color,
      fontFamily: 'Caveat',
      fontWeight: FontWeight.w700,
    ),
  };

  /// Font seçici balonundaki etiket boyutu — ince/küçük görünen fontlar
  /// (el yazısı, dar büyük harf) balonda diğerleriyle dengeli dursun.
  double get chipFontSize => switch (this) {
    OverlayFont.bold => 17,
    OverlayFont.script => 19,
    _ => 14.5,
  };
}

/// JSON/sunucudaki değeri fonta çevirir; bilinmeyen/boş değer → modern.
OverlayFont overlayFontFromWire(String? wire) {
  for (final font in OverlayFont.values) {
    if (font.wireName == wire) return font;
  }
  return OverlayFont.modern;
}

/// Paketlenen fontların OFL lisanslarını uygulamanın lisans sayfasına ekler
/// (OFL, fontla birlikte lisansın dağıtılmasını şart koşar). main()'de bir
/// kez çağrılır; metinler yalnızca lisans sayfası açılınca yüklenir.
void registerOverlayFontLicenses() {
  const fonts = {
    'Playfair Display': 'PlayfairDisplay',
    'Courier Prime': 'CourierPrime',
    'Bebas Neue': 'BebasNeue',
    'Caveat': 'Caveat',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in fonts.entries) {
      final text = await rootBundle.loadString(
        'assets/fonts/OFL-${entry.value}.txt',
      );
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}
