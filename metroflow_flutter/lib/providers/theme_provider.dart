import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.light;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('theme_mode');
    ThemeMode newMode = ThemeMode.light;
    if (themeString != null) {
      switch (themeString) {
        case 'light':
          newMode = ThemeMode.light;
          break;
        case 'dark':
          newMode = ThemeMode.dark;
          break;
        default:
          newMode = ThemeMode.light;
      }
    }
    state = newMode;
    AppTheme.setThemeMode(newMode);
  }

  Future<void> toggleTheme(ThemeMode mode) async {
    state = mode;
    AppTheme.setThemeMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}
