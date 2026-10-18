import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => code != null ? 'AppException [$code]: $message' : 'AppException: $message';

  void showSnackbar({String title = 'Terjadi Kesalahan'}) {
    showErrorSnackbar(this, title: title);
  }

  static void showErrorSnackbar(dynamic error, {String title = 'Terjadi Kesalahan'}) {
    String msg;
    if (error is AppException) {
      msg = error.message;
    } else if (error is Exception) {
      msg = error.toString().replaceFirst('Exception: ', '');
    } else {
      msg = error?.toString() ?? 'Terjadi kesalahan tidak terduga';
    }

    if (Get.isSnackbarOpen) {
      Get.closeCurrentSnackbar();
    }

    Get.snackbar(
      title,
      msg,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.shade800,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
      icon: const Icon(Icons.error_outline, color: Colors.white),
    );
  }
}

class LimitReachedException extends AppException {
  final int limit;

  const LimitReachedException(
    super.message, {
    required this.limit,
    super.code = 'LIMIT_REACHED',
  });
}


