import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemeService extends GetxService {
  static ThemeService get to => Get.find<ThemeService>();

  static const String _themeKey = 'app_theme_mode';
  static const String _primaryColorKey = 'app_primary_color';

  static const List<Map<String, dynamic>> availableColors = [
    {'name': 'Biru POS', 'color': Color(0xFF1976D2)},
    {'name': 'Hijau Emerald', 'color': Color(0xFF00796B)},
    {'name': 'Indigo Royal', 'color': Color(0xFF3F51B5)},
    {'name': 'Oranye Hangat', 'color': Color(0xFFE65100)},
    {'name': 'Ungu Elegan', 'color': Color(0xFF6A1B9A)},
  ];

  late final SharedPreferences _prefs;
  final Rx<ThemeMode> _themeMode = ThemeMode.system.obs;
  final Rx<Color> _primaryColor = AppTheme.defaultSeedColor.obs;

  ThemeMode get themeMode => _themeMode.value;
  bool get isDarkMode => _themeMode.value == ThemeMode.dark;
  Color get primaryColor => _primaryColor.value;

  Future<ThemeService> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedMode = _prefs.getString(_themeKey);

    if (savedMode == 'light') {
      _themeMode.value = ThemeMode.light;
    } else if (savedMode == 'dark') {
      _themeMode.value = ThemeMode.dark;
    } else {
      _themeMode.value = ThemeMode.system;
    }

    final savedColor = _prefs.getInt(_primaryColorKey);
    if (savedColor != null) {
      _primaryColor.value = Color(savedColor);
    }

    return this;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode.value = mode;
    String value = 'system';
    if (mode == ThemeMode.light) {
      value = 'light';
    } else if (mode == ThemeMode.dark) {
      value = 'dark';
    }

    await _prefs.setString(_themeKey, value);
    Get.changeThemeMode(mode);
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor.value = color;
    await _prefs.setInt(_primaryColorKey, color.toARGB32());
    Get.changeTheme(AppTheme.lightTheme(seedColor: color));
    Get.changeThemeMode(_themeMode.value);
  }

  Future<void> switchTheme() async {
    if (_themeMode.value == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}
