import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final savedTheme = await SecureStorage.read(_themeKey);
    if (savedTheme != null) {
      _isDarkMode = savedTheme == 'dark';
      notifyListeners();
    }
    await _syncThemeFromBackend();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(_isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setThemeMode(ThemeMode mode, {bool syncRemote = true}) async {
    _isDarkMode = mode == ThemeMode.dark;
    await SecureStorage.write(_themeKey, _isDarkMode ? 'dark' : 'light');
    notifyListeners();
    if (syncRemote) {
      await _saveThemeToBackend(_isDarkMode ? 'dark' : 'light');
    }
  }

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> _syncThemeFromBackend() async {
    try {
      final me = await AuthRepository().getMe();
      final parsed = _parseThemeFromMe(me);
      if (parsed == null) return;
      final isDark = parsed == 'dark';
      if (isDark == _isDarkMode) return;
      _isDarkMode = isDark;
      await SecureStorage.write(_themeKey, parsed);
      notifyListeners();
    } catch (_) {
      // User may be logged out or backend may not support this field.
    }
  }

  String? _parseThemeFromMe(Map<String, dynamic> me) {
    String? normalize(dynamic value) {
      if (value == null) return null;
      final raw = value.toString().trim().toLowerCase();
      if (raw.isEmpty) return null;
      if (raw == 'dark' || raw == '1' || raw == 'true') return 'dark';
      if (raw == 'light' || raw == '0' || raw == 'false') return 'light';
      return null;
    }

    final preferences = me['preferences'] is Map<String, dynamic>
        ? me['preferences'] as Map<String, dynamic>
        : null;
    final settings = me['settings'] is Map<String, dynamic>
        ? me['settings'] as Map<String, dynamic>
        : null;

    return normalize(me['theme_mode']) ??
        normalize(me['themeMode']) ??
        normalize(me['app_theme']) ??
        normalize(me['appTheme']) ??
        normalize(preferences?['theme_mode']) ??
        normalize(preferences?['themeMode']) ??
        normalize(settings?['theme_mode']) ??
        normalize(settings?['themeMode']);
  }

  Future<void> _saveThemeToBackend(String mode) async {
    final repo = AuthRepository();
    final payloads = <Map<String, dynamic>>[
      {'theme_mode': mode},
      {'themeMode': mode},
      {
        'preferences': {'theme_mode': mode},
      },
      {
        'settings': {'theme_mode': mode},
      },
    ];

    for (final payload in payloads) {
      try {
        await repo.updateMe(payload);
        return;
      } catch (_) {
        // Try next payload format.
      }
    }
  }
}
