import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../routes/app_pages.dart';
import '../services/auth_service.dart';

class AuthMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    // Pastikan AuthService sudah tersedia
    if (!Get.isRegistered<AuthService>()) {
      return null;
    }

    final authService = AuthService.to;

    // 1. Jika toko belum pernah di-setup, wajib ke /setup
    if (!authService.hasStore) {
      if (route == Routes.SETUP) return null;
      return const RouteSettings(name: Routes.SETUP);
    }

    // 2. Jika toko sudah ada tapi mengakses /setup, arahkan ke beranda
    if (route == Routes.SETUP) {
      return const RouteSettings(name: Routes.HOME);
    }

    // 3. Jika toko mewajibkan login dan pengguna belum login:
    if (authService.requireLogin && !authService.isLoggedIn) {
      if (route == Routes.LOGIN) return null;
      return const RouteSettings(name: Routes.LOGIN);
    }

    // 4. Jika pengguna sudah login tapi mengakses /login, arahkan ke beranda
    if (route == Routes.LOGIN && authService.isLoggedIn) {
      return const RouteSettings(name: Routes.HOME);
    }

    return null;
  }
}

