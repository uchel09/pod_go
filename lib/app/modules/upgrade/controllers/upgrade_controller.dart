import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_config.dart';
import '../../../core/features/feature_enum.dart';
import '../../../core/features/tier_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/repositories/license_repository.dart';
import '../../../data/services/payment_gateway.dart';
import '../../../routes/app_pages.dart';

class UpgradeController extends GetxController {
  final LicenseRepository _licenseRepo = Get.find<LicenseRepository>();

  Rx<Tier> get currentTier => FeatureGate.to.tier;

  final selectedDuration = PlanDuration.monthly.obs;
  final isLoading = false.obs;

  bool get isSimulationMode => AppConfig.simulationMode;

  bool get canManageLicense {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.licenseManage);
  }

  Feature? get requestedFeature =>
      Get.arguments is Map ? Get.arguments['feature'] as Feature? : null;

  void setDuration(PlanDuration duration) {
    selectedDuration.value = duration;
  }

  int getSemiPrice() {
    return selectedDuration.value == PlanDuration.monthly
        ? AppConfig.priceSemiMonthly
        : AppConfig.priceSemiYearly;
  }

  int getPremiumPrice() {
    return selectedDuration.value == PlanDuration.monthly
        ? AppConfig.pricePremiumMonthly
        : AppConfig.pricePremiumYearly;
  }

  Future<void> handleSelectTier(Tier targetTier) async {
    if (!canManageLicense) {
      if (Get.context != null) {
        Get.snackbar(
          'Akses Ditolak',
          'Hanya pemilik toko (Owner) yang berhak mengelola lisensi toko.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
        );
      }
      return;
    }

    if (targetTier == currentTier.value) {
      return;
    }

    if (targetTier == Tier.free) {
      // Konfirmasi penurunan tier (Downgrade ke Gratis)
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Konfirmasi Turun ke Paket Gratis'),
          content: const Text(
            'Dengan menurunkan paket ke Gratis:\n'
            '- Fitur Semi-Premium (Opname, Pembelian, Import/Export, Auto-backup) akan terkunci kembali.\n'
            '- Produk di atas 10 akan menjadi read-only.\n'
            '- Data transaksi dan stok lama tetap aman dan tidak akan dihapus.\n\n'
            'Lanjutkan penurunan paket?',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
              onPressed: () => Get.back(result: true),
              child: const Text('Ya, Turunkan ke Gratis'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        isLoading.value = true;
        try {
          await _licenseRepo.resetToFree();
          if (Get.context != null) {
            Get.snackbar(
              'Paket Diturunkan',
              'Sistem kini kembali menggunakan paket Gratis.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange.shade800,
              colorText: Colors.white,
            );
          }
        } catch (e) {
          if (Get.context != null) {
            Get.snackbar('Gagal Mengubah Paket', e.toString());
          }
        } finally {
          isLoading.value = false;
        }
      }
      return;
    }

    // Arahkan ke Checkout Simulasi
    final price = targetTier == Tier.semi ? getSemiPrice() : getPremiumPrice();
    final plan = Plan(
      tier: targetTier,
      duration: selectedDuration.value,
      price: price,
    );

    Get.toNamed(
      Routes.CHECKOUT_SIMULATION,
      arguments: {'plan': plan},
    );
  }
}
