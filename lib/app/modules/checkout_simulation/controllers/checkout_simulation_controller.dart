import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_config.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/services/payment_gateway.dart';

class CheckoutSimulationController extends GetxController {
  final PaymentGateway _paymentGateway = Get.find<PaymentGateway>();

  final Rx<Plan?> plan = Rx<Plan?>(null);
  final RxString selectedMethod = 'qris'.obs;
  final RxBool isLoading = false.obs;
  final Rx<PaymentResult?> paymentResult = Rx<PaymentResult?>(null);
  final RxString errorMessage = ''.obs;

  bool get isSimulationMode => AppConfig.simulationMode;

  bool get canManageLicense {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.licenseManage);
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['plan'] is Plan) {
      plan.value = args['plan'] as Plan;
    }

    if (!isSimulationMode) {
      errorMessage.value =
          'Checkout simulasi hanya aktif di mode simulasi (kSimulationMode = true).';
    } else if (!canManageLicense) {
      errorMessage.value =
          'Akses ditolak: Anda tidak memiliki izin untuk mengelola lisensi toko (license.manage).';
    } else if (plan.value == null) {
      errorMessage.value = 'Paket langganan tidak valid atau belum dipilih.';
    }
  }

  void selectMethod(String method) {
    selectedMethod.value = method;
  }

  void _showFeedback(String title, String message, {Color? backgroundColor}) {
    if (Get.context != null) {
      Get.snackbar(
        title,
        message,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: backgroundColor ?? Colors.red.shade800,
        colorText: Colors.white,
      );
    }
  }

  Future<void> processPayment({bool simulateFailure = false}) async {
    final currentPlan = plan.value;
    if (currentPlan == null) return;

    if (!canManageLicense) {
      _showFeedback(
        'Akses Ditolak',
        'Hanya pemilik toko (Owner) yang berhak melakukan transaksi lisensi.',
      );
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';

    try {
      final result = await _paymentGateway.pay(
        currentPlan,
        paymentMethod: selectedMethod.value,
        simulateFailure: simulateFailure,
      );
      paymentResult.value = result;

      if (!result.isSuccess) {
        _showFeedback(
          'Pembayaran Gagal (Simulasi)',
          result.errorMessage ?? 'Transaksi ditolak oleh sistem simulasi.',
        );
      }
    } catch (e) {
      _showFeedback('Kesalahan Transaksi', e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
