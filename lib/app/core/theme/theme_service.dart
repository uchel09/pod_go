import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends GetxService {
  static ThemeService get to => Get.find<ThemeService>();

  static const String _themeKey = 'app_theme_mode';

  late final SharedPreferences _prefs;
  final Rx<ThemeMode> _themeMode = ThemeMode.system.obs;

  ThemeMode get themeMode => _themeMode.value;
  bool get isDarkMode => _themeMode.value == ThemeMode.dark;

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

  Future<void> switchTheme() async {
    if (_themeMode.value == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}

