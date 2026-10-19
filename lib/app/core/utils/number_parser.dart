/// Parser angka dan mata uang Rupiah yang toleran terhadap berbagai format input UMKM
/// Contoh: "12.500", "12500", "Rp 12.500", "12.500,00", "12,500.00", "12500,50"
class NumberParser {
  NumberParser._();

  /// Mem-parsing nilai menjadi integer Rupiah toleran.
  /// Mengembalikan [null] bila nilai kosong atau bukan format angka yang valid.
  static int? parseRupiah(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.round();

    final str = value.toString().trim();
    if (str.isEmpty) return null;

    // Bersihkan karakter mata uang, spasi, simbol kurung negatif
    bool isNegative = false;
    String cleaned = str.toUpperCase().replaceAll('RP', '').replaceAll('IDR', '').replaceAll(' ', '').trim();

    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      isNegative = true;
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    } else if (cleaned.startsWith('-')) {
      isNegative = true;
      cleaned = cleaned.substring(1).trim();
    }

    // Hilangkan semua karakter kecuali digit, titik, dan koma
    cleaned = cleaned.replaceAll(RegExp(r'[^\d.,]'), '');
    if (cleaned.isEmpty) return null;

    final dotIndex = cleaned.lastIndexOf('.');
    final commaIndex = cleaned.lastIndexOf(',');

    double? parsedDouble;

    if (dotIndex != -1 && commaIndex != -1) {
      // Ada titik dan koma sekaligus
      if (dotIndex < commaIndex) {
        // Format Indonesia/Eropa: "12.500,50" -> titik adalah ribuan, koma adalah desimal
        final noDots = cleaned.replaceAll('.', '');
        final standardDecimal = noDots.replaceAll(',', '.');
        parsedDouble = double.tryParse(standardDecimal);
      } else {
        // Format US: "12,500.50" -> koma adalah ribuan, titik adalah desimal
        final noCommas = cleaned.replaceAll(',', '');
        parsedDouble = double.tryParse(noCommas);
      }
    } else if (commaIndex != -1) {
      // Hanya ada koma
      final commaCount = ','.allMatches(cleaned).length;
      if (commaCount > 1) {
        // Banyak koma -> pemisah ribuan "1,250,000"
        final noCommas = cleaned.replaceAll(',', '');
        parsedDouble = double.tryParse(noCommas);
      } else {
        // 1 koma: cek jumlah digit di belakang koma
        final afterComma = cleaned.substring(commaIndex + 1);
        if (afterComma.length == 3 && cleaned.length >= 5) {
          // Format ribuan dengan koma "12,500"
          final noCommas = cleaned.replaceAll(',', '');
          parsedDouble = double.tryParse(noCommas);
        } else {
          // Desimal dengan koma "12500,50" atau "12,5"
          final standardDecimal = cleaned.replaceAll(',', '.');
          parsedDouble = double.tryParse(standardDecimal);
        }
      }
    } else if (dotIndex != -1) {
      // Hanya ada titik
      final dotCount = '.'.allMatches(cleaned).length;
      if (dotCount > 1) {
        // Banyak titik -> pemisah ribuan "1.250.000"
        final noDots = cleaned.replaceAll('.', '');
        parsedDouble = double.tryParse(noDots);
      } else {
        // 1 titik: cek jumlah digit di belakang titik
        final afterDot = cleaned.substring(dotIndex + 1);
        if (afterDot.length == 3 && cleaned.length >= 5) {
          // Format ribuan Indonesia: "12.500", "1.000"
          final noDots = cleaned.replaceAll('.', '');
          parsedDouble = double.tryParse(noDots);
        } else {
          // Desimal dengan titik "12500.50" atau "12.5"
          parsedDouble = double.tryParse(cleaned);
        }
      }
    } else {
      // Hanya digit murni
      parsedDouble = double.tryParse(cleaned);
    }

    if (parsedDouble == null || parsedDouble.isNaN || parsedDouble.isInfinite) {
      return null;
    }

    final result = parsedDouble.round();
    return isNegative ? -result : result;
  }

  /// Mem-parsing kuantitas (integer biasa/stok)
  static int? parseInt(dynamic value) {
    return parseRupiah(value);
  }
}

