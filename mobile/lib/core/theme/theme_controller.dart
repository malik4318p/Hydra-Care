import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers the user's light/dark preference across app restarts.
///
/// Defaults to the device setting until a preference is saved.
class ThemeController extends ChangeNotifier {
  ThemeController({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'theme_mode';

  final FlutterSecureStorage _storage;

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _key);
      if (saved == 'dark') {
        _mode = ThemeMode.dark;
      } else if (saved == 'light') {
        _mode = ThemeMode.light;
      }
    } catch (_) {
      // Keep the system default if the saved preference cannot be read.
    }
    notifyListeners();
  }

  Future<void> setDark(bool enabled) async {
    _mode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: enabled ? 'dark' : 'light');
    } catch (_) {
      // The toggle still works for this session even if saving fails.
    }
  }
}
