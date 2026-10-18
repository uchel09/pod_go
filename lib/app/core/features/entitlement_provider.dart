import '../../data/local/app_database.dart';
import '../../data/repositories/license_repository.dart';
import 'tier_enum.dart';

/// Interface abstraksi sumber tier / lisensi agar implementasi pembayaran / backend
/// dapat ditukar dengan mudah tanpa mengubah logika internal aplikasi.
abstract class EntitlementProvider {
  /// Mendapatkan tier yang aktif saat ini
  Future<Tier> currentTier();

  /// Mengamati perubahan tier secara real-time / reaktif
  Stream<Tier> watchTier();
}

/// Implementasi simulasi lokal yang membaca status lisensi dari tabel `licenses` Drift.
class SimulatedEntitlementProvider implements EntitlementProvider {
  final LicenseRepository _licenseRepo;

  SimulatedEntitlementProvider(this._licenseRepo);

  @override
  Future<Tier> currentTier() async {
    final license = await _licenseRepo.getActiveLicense();
    return _evaluateLicense(license);
  }

  @override
  Stream<Tier> watchTier() {
    return _licenseRepo.watchActiveLicense().map(_evaluateLicense).distinct();
  }

  /// Menilai keabsahan lisensi:
  /// - Jika lisensi tidak ada atau status bukan 'active' -> Tier.free
  /// - Jika sudah melewati tanggal `expiresAt` (kedaluwarsa) -> Tier.free
  /// - Jika aktif dan valid -> kembalikan tier sesuai data lisensi
  Tier _evaluateLicense(License? license) {
    if (license == null) return Tier.free;
    if (license.status.toLowerCase() != 'active') return Tier.free;

    if (license.expiresAt != null && license.expiresAt!.isBefore(DateTime.now())) {
      return Tier.free;
    }

    return Tier.fromString(license.tier);
  }
}

