import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class ThemeState {
  final ThemeMode mode;
  final bool isLoading;

  ThemeState({required this.mode, this.isLoading = false});

  ThemeState copyWith({ThemeMode? mode, bool? isLoading}) {
    return ThemeState(
      mode: mode ?? this.mode,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    _loadTheme();
    return ThemeState(mode: ThemeMode.light);
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
    state = ThemeState(mode: newMode);
    AppTheme.setThemeMode(newMode);
  }

  Future<void> toggleTheme(ThemeMode mode) async {
    state = state.copyWith(isLoading: true);
    
    // Add a small delay to show the spinner
    await Future.delayed(const Duration(milliseconds: 300));
    
    state = state.copyWith(mode: mode, isLoading: false);
    AppTheme.setThemeMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}
