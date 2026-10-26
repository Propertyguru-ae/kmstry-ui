import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

/// Device preference shared by personal and venue contexts, not profile data.
class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  ThemeProvider({
    Future<String?> Function()? readPreference,
    Future<void> Function(String)? writePreference,
  }) : _readPreference =
           readPreference ?? (() => SecureStorage.read(_themeKey)),
       _writePreference =
           writePreference ??
           ((value) => SecureStorage.write(_themeKey, value)) {
    ready = _restore();
  }

  final Future<String?> Function() _readPreference;
  final Future<void> Function(String) _writePreference;
  late final Future<void> ready;
  ThemeMode _mode = ThemeMode.system;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  ThemeMode get themeMode => _mode;

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final saved = await _readPreference();
      if (_disposed || revision != _revision) return;
      _mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      notifyListeners();
    } catch (_) {
      // Storage failure must not block startup or erase an existing preference.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) {
    _revision++;
    _mode = mode;
    notifyListeners();
    // Serialize rapid selections without delaying the visual change.
    final write = _writes
        .catchError((Object _) {})
        .then((_) => _writePreference(mode.name));
    _writes = write;
    return write;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
