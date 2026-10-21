import '../config/app_config.dart';
import 'feature_enum.dart';
import 'tier_enum.dart';

/// Matriks pemetaan antara Tier Lisensi dan ketersediaan Fitur aplikasi POS Me.
class TierFeatureMatrix {
  TierFeatureMatrix._();

  /// Himpunan fitur yang terbuka untuk tier Semi Premium
  static const Set<Feature> _semiFeatures = {
    Feature.unlimitedProducts,
    Feature.stockOpname,
    Feature.purchases,
    Feature.importExport,
    Feature.fullReports,
    Feature.autoBackup,
    Feature.expenses,
  };

  /// Himpunan fitur tambahan yang hanya terbuka untuk tier Premium (Tim & Multi-device)
  static const Set<Feature> _premiumFeatures = {
    ..._semiFeatures,
    Feature.teamManagement,
    Feature.attendance,
    Feature.customRoles,
    Feature.hostClient,
    Feature.shifts,
    Feature.voidApproval,
  };

  /// Memeriksa apakah [feature] diizinkan untuk [tier] yang diberikan
  static bool isEnabled(Tier tier, Feature feature) {
    switch (tier) {
      case Tier.free:
        // Tier Gratis hanya mencakup fitur dasar POS (kasir, scanner, backup manual, laporan dasar)
        return false;
      case Tier.semi:
        return _semiFeatures.contains(feature);
      case Tier.premium:
        return _premiumFeatures.contains(feature);
    }
  }

  /// Batas maksimal produk aktif untuk tier tertentu.
  /// Mengembalikan `null` jika tidak terbatas.
  static int? productLimit(Tier tier) {
    switch (tier) {
      case Tier.free:
        return kFreeProductLimit;
      case Tier.semi:
      case Tier.premium:
        return null;
    }
  }

  /// Daftar semua fitur yang aktif pada tier tertentu
  static Set<Feature> activeFeatures(Tier tier) {
    switch (tier) {
      case Tier.free:
        return const {};
      case Tier.semi:
        return _semiFeatures;
      case Tier.premium:
        return _premiumFeatures;
    }
  }
}

