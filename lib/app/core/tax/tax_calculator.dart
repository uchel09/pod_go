/// Model hasil kalkulasi pajak terpadu.
class TaxCalculationResult {
  final int basis; // Subtotal setelah diskon
  final int rateBps; // Basis poin (1100 = 11%, 0 - 10000)
  final String mode; // 'exclusive' | 'inclusive'
  final int tax; // Nilai pajak (Rupiah integer)
  final int total; // Total akhir transaksi (Rupiah integer)

  const TaxCalculationResult({
    required this.basis,
    required this.rateBps,
    required this.mode,
    required this.tax,
    required this.total,
  });

  /// Persentase dalam string yang mudah dibaca, misal: "11%" atau "11.5%"
  String get ratePercentString {
    if (rateBps % 100 == 0) {
      return '${rateBps ~/ 100}%';
    }
    final percent = rateBps / 100.0;
    return '${percent.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}%';
  }
}

/// TaxCalculator murni: satu-satunya tempat menghitung pajak di aplikasi.
///
/// Seluruh perhitungan menggunakan aritmatika integer Rupiah murni tanpa `double`
/// untuk mencegah precision loss.
///
/// Aturan:
/// - Exclusive: tax = round(basis * rateBps / 10000)
///   Total = basis + tax
/// - Inclusive: tax = basis - round(basis * 10000 / (10000 + rateBps))
///   Total = basis (pajak sudah termasuk dalam harga jual)
/// - Basis = subtotal setelah diskon.
/// - Pembulatan: half-up ke integer Rupiah (misal .5 dibulatkan ke atas).
class TaxCalculator {
  static const String modeExclusive = 'exclusive';
  static const String modeInclusive = 'inclusive';

  /// Menghitung pajak eksklusif dengan pembulatan half-up integer Rupiah:
  /// `tax = ((basis * rateBps) + 5000) ~/ 10000`
  static int calculateExclusive(int basis, int rateBps) {
    if (basis <= 0 || rateBps <= 0) return 0;
    return (basis * rateBps + 5000) ~/ 10000;
  }

  /// Menghitung pajak inklusif dengan pembulatan half-up integer Rupiah:
  /// `den = 10000 + rateBps`
  /// `net = ((basis * 10000) + (den ~/ 2)) ~/ den`
  /// `tax = basis - net`
  static int calculateInclusive(int basis, int rateBps) {
    if (basis <= 0 || rateBps <= 0) return 0;
    final den = 10000 + rateBps;
    final net = (basis * 10000 + (den ~/ 2)) ~/ den;
    return basis - net;
  }

  /// Menghitung hasil kalkulasi pajak secara menyeluruh.
  static TaxCalculationResult calculate({
    required int basis,
    required int rateBps,
    required String mode,
    bool isEnabled = true,
  }) {
    final validBasis = basis > 0 ? basis : 0;
    final clampedRate = rateBps.clamp(0, 10000);

    if (!isEnabled || validBasis == 0 || clampedRate == 0) {
      return TaxCalculationResult(
        basis: validBasis,
        rateBps: clampedRate,
        mode: mode,
        tax: 0,
        total: validBasis,
      );
    }

    final isInclusive = mode.toLowerCase() == modeInclusive;
    if (isInclusive) {
      final tax = calculateInclusive(validBasis, clampedRate);
      return TaxCalculationResult(
        basis: validBasis,
        rateBps: clampedRate,
        mode: modeInclusive,
        tax: tax,
        total: validBasis,
      );
    } else {
      final tax = calculateExclusive(validBasis, clampedRate);
      return TaxCalculationResult(
        basis: validBasis,
        rateBps: clampedRate,
        mode: modeExclusive,
        tax: tax,
        total: validBasis + tax,
      );
    }
  }
}

