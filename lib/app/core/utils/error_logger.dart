import 'package:flutter/foundation.dart';

/// Logger kesalahan sederhana tanpa membocorkan data sensitif pengguna.
class AppErrorLogger {
  AppErrorLogger._();

  static final List<String> _inMemoryLogs = [];

  static List<String> get recentLogs => List.unmodifiable(_inMemoryLogs);

  /// Menangani Flutter framework error
  static void onFlutterError(FlutterErrorDetails details) {
    final sanitizedMessage = _sanitize(details.exceptionAsString());
    final entry = '[${DateTime.now().toIso8601String()}] [FLUTTER_ERROR] $sanitizedMessage';
    _append(entry);

    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  }

  /// Menangani async platform error yang tidak tertangkap di widget tree
  static bool onPlatformError(Object error, StackTrace stack) {
    final sanitizedMessage = _sanitize(error.toString());
    final entry = '[${DateTime.now().toIso8601String()}] [PLATFORM_ERROR] $sanitizedMessage';
    _append(entry);

    if (kDebugMode) {
      debugPrint(entry);
      debugPrint(stack.toString());
    }
    // Return true agar error tidak menyebabkan crash/force close aplikasi
    return true;
  }

  /// Membersihkan data sensitif (password, PIN, recovery code, token) dari string error
  static String _sanitize(String text) {
    var result = text;
    // Sensor password / pin / token / secret
    result = result.replaceAll(RegExp(r'(password|pin|secret|token|recovery[_\s]?code)\s*[:=]\s*[^\s,;]+', caseSensitive: false), r'$1: [REDACTED]');
    // Sensor format kode recovery 16 karakter (XXXX-XXXX-XXXX-XXXX)
    result = result.replaceAll(RegExp(r'\b[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\b'), '[REDACTED_CODE]');
    return result;
  }

  static void _append(String entry) {
    _inMemoryLogs.add(entry);
    if (_inMemoryLogs.length > 200) {
      _inMemoryLogs.removeAt(0);
    }
  }
}
