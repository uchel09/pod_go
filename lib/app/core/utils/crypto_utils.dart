import 'dart:math';
import 'package:bcrypt/bcrypt.dart';

class CryptoUtils {
  CryptoUtils._();

  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Tanpa O, 0, I, 1 agar tidak membingungkan

  /// Menghasilkan Recovery Code acak 16 karakter dalam format XXXX-XXXX-XXXX-XXXX
  static String generateRecoveryCode() {
    final random = Random.secure();
    final buffer = StringBuffer();

    for (int i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(_chars[random.nextInt(_chars.length)]);
    }

    return buffer.toString();
  }

  /// Membersihkan input kode (hapus spasi & strip, jadikan uppercase)
  static String normalizeCode(String code) {
    return code.replaceAll('-', '').replaceAll(' ', '').toUpperCase().trim();
  }

  /// Melakukan hashing password / PIN / recovery code dengan bcrypt
  static String hashSecret(String secret) {
    return BCrypt.hashpw(secret, BCrypt.gensalt());
  }

  /// Memverifikasi secret dengan hash bcrypt
  static bool verifySecret(String secret, String hash) {
    try {
      return BCrypt.checkpw(secret, hash);
    } catch (_) {
      return false;
    }
  }
}

