import 'package:get/get.dart';

import '../../routes/app_pages.dart';
import '../features/entitlement_provider.dart';
import '../features/feature_enum.dart';
import '../features/tier_enum.dart';
import '../features/tier_feature_matrix.dart';

/// Layanan evaluasi fitur berdasarkan tier lisensi aktif (Feature Gating).
class FeatureGate extends GetxService {
  static FeatureGate get to => Get.find<FeatureGate>();

  final EntitlementProvider _provider;

  FeatureGate(this._provider);

  /// Tingkatan tier lisensi yang sedang aktif (Reaktif)
  final Rx<Tier> tier = Tier.free.obs;

  /// Inisialisasi awal dan observasi perubahan lisensi secara reaktif
  Future<FeatureGate> init() async {
    tier.value = await _provider.currentTier();
    _provider.watchTier().listen((newTier) {
      tier.value = newTier;
    });
    return this;
  }

  /// Batas maksimal produk aktif untuk tier saat ini (null jika unlimited)
  int? get productLimit => TierFeatureMatrix.productLimit(tier.value);

  /// Memeriksa apakah fitur diizinkan untuk tier saat ini.
  /// Menerima parameter bertipe [Feature] atau [String] (untuk kompatibilitas alias).
  bool isEnabled(dynamic feature) {
    if (feature is Feature) {
      return TierFeatureMatrix.isEnabled(tier.value, feature);
    }

    if (feature is String) {
      switch (feature) {
        case 'team_mode':
        case 'multi_user':
          return TierFeatureMatrix.isEnabled(tier.value, Feature.teamManagement);
        default:
          final matched = Feature.values.firstWhereOrNull(
            (f) => f.name.toLowerCase() == feature.toLowerCase(),
          );
          if (matched != null) {
            return TierFeatureMatrix.isEnabled(tier.value, matched);
          }
      }
    }

    return false;
  }

  /// Memeriksa ketersediaan [feature]. Jika belum tersedia pada tier saat ini,
  /// secara otomatis mengarahkan pengguna ke halaman Upgrade (/upgrade).
  bool requireFeature(Feature feature) {
    if (isEnabled(feature)) {
      return true;
    }

    Get.toNamed(Routes.UPGRADE, arguments: {'feature': feature});
    return false;
  }
}
