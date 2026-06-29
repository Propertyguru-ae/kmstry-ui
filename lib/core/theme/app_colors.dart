import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Logo brand renkleri (kesin) ──────────────────────────────────────────
  static const Color brand    = Color(0xFF3D1F8C); // koyu mor — ana accent
  static const Color magenta  = Color(0xFFE020D8); // sol üst
  static const Color teal     = Color(0xFF1FD9A8); // sağ üst
  static const Color blue     = Color(0xFF1A9FE8); // sol alt
  static const Color orange   = Color(0xFFF08838); // sağ alt

  // ── Dark mode varyantları (koyu bg üzerinde okunaklı) ───────────────────
  static const Color blueDark    = Color(0xFF4EC8FF); // blue parlaklaştırılmış
  static const Color magentaDark = Color(0xFFF040EC); // magenta parlaklaştırılmış
  static const Color tealDark    = Color(0xFF3AEDC0); // teal parlaklaştırılmış

  // ── Light mode varyantları (beyaz bg üzerinde kontrast) ─────────────────
  static const Color blueLight   = Color(0xFF0E7EC4); // blue koyulaştırılmış
  static const Color brandLight  = Color(0xFF5B21B6); // brand mor, light için

  // ── Arka plan & surface ──────────────────────────────────────────────────
  static const Color darkBg      = Color(0xFF06091A);
  static const Color darkSurface = Color(0xFF0B1322);

  // ── Metin ───────────────────────────────────────────────────────────────
  static const Color darkTextPrimary   = Color(0xFFF4F6F8);
  static const Color darkTextSecondary = Color(0xFFA6B1BA);
  static const Color lightTextPrimary  = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF5D6B7B);

  // ── Gradient çiftleri ────────────────────────────────────────────────────
  static const List<Color> gradientDark  = [blueDark, magentaDark];   // dark mode hero
  static const List<Color> gradientLight = [blue, brand];             // light mode hero
}
