import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/local/daos/customer_dao.dart';
import '../../../data/repositories/customer_repository.dart';

class CustomerDetailController extends GetxController {
  final CustomerRepository _customerRepo = Get.find<CustomerRepository>();

  final customerId = 0.obs;
  final customerWithBalance = Rxn<CustomerWithBalance>();
  final ledger = <CustomerLedgerItem>[].obs;
  final isLoading = true.obs;
  final isSubmitting = false.obs;

  bool get canManage => PermissionService.to.can(PermissionKeys.customerManage);
  bool get canCollect =>
      PermissionService.to.can(PermissionKeys.customerCollect);
  bool get canView => PermissionService.to.can(PermissionKeys.customerView);
  bool get hasCustomerFeature =>
      FeatureGate.to.isEnabled(Feature.customerCredit);

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is int) {
      customerId.value = args;
    } else if (args is String) {
      customerId.value = int.tryParse(args) ?? 0;
    }

    if (customerId.value > 0 && hasCustomerFeature && canView) {
      loadCustomerDetails();
    } else {
      isLoading.value = false;
    }
  }

  Future<void> loadCustomerDetails() async {
    isLoading.value = true;
    try {
      final cust = await _customerRepo.getCustomer(customerId.value);
      if (cust == null) {
        Get.snackbar(
          'Error',
          'Pelanggan tidak ditemukan.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      customerWithBalance.value = cust;

      final ledgerItems = await _customerRepo.getCustomerLedger(
        customerId.value,
      );
      ledger.assignAll(ledgerItems);
    } catch (e) {
      Get.snackbar(
        'Error',
        'Gagal memuat detail pelanggan: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> recordPayment({
    required int amount,
    required String method,
    String? note,
  }) async {
    if (amount <= 0) {
      Get.snackbar(
        'Perhatian',
        'Jumlah pembayaran harus lebih dari 0.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final currentBalance = customerWithBalance.value?.balance ?? 0;
    if (amount > currentBalance) {
      Get.snackbar(
        'Gagal',
        'Pembayaran (${formatRupiah(amount)}) melebihi sisa hutang (${formatRupiah(currentBalance)}).',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    isSubmitting.value = true;
    try {
      await _customerRepo.recordPayment(
        RecordCustomerPaymentInput(
          customerId: customerId.value,
          amount: amount,
          method: method,
          note: note,
          deviceId: 'device-main',
        ),
      );
      await loadCustomerDetails();
      Get.snackbar(
        'Sukses',
        'Pembayaran sebesar ${formatRupiah(amount)} berhasil dicatat.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      Get.snackbar('Gagal', e.message, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'Gagal',
        'Terjadi kesalahan: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<void> toggleActiveStatus() async {
    final cust = customerWithBalance.value?.customer;
    if (cust == null) return;

    try {
      if (cust.isActive) {
        await _customerRepo.deactivateCustomer(cust.id);
        Get.snackbar(
          'Sukses',
          'Pelanggan dinonaktifkan.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        await _customerRepo.activateCustomer(cust.id);
        Get.snackbar(
          'Sukses',
          'Pelanggan diaktifkan kembali.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      await loadCustomerDetails();
    } on AppException catch (e) {
      Get.snackbar('Gagal', e.message, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'Gagal',
        'Terjadi kesalahan: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> updateCustomer(UpdateCustomerInput input) async {
    try {
      await _customerRepo.updateCustomer(input);
      await loadCustomerDetails();
      Get.snackbar(
        'Sukses',
        'Data pelanggan berhasil diperbarui.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      Get.snackbar('Gagal', e.message, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'Gagal',
        'Terjadi kesalahan: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> deleteCustomer() async {
    try {
      await _customerRepo.deleteCustomer(customerId.value);
      Get.back(result: true);
      Get.snackbar(
        'Sukses',
        'Pelanggan berhasil dihapus.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      Get.snackbar('Gagal', e.message, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
        'Gagal',
        'Terjadi kesalahan: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void copyWhatsAppReminder() {
    final data = customerWithBalance.value;
    if (data == null) return;

    final store = AuthService.to.currentStore.value;
    final storeName = store?.name ?? 'Toko Kami';
    final customerName = data.customer.name;
    final balance = formatRupiah(data.balance);

    final message =
        '''Halo Kak $customerName,
Mengingatkan bahwa masih ada sisa kasbon/hutang di $storeName sebesar $balance.
Mohon kesediaannya untuk melakukan pembayaran. Terima kasih atas kerja samanya 🙏''';

    Clipboard.setData(ClipboardData(text: message));
    Get.snackbar(
      'Berhasil Disalin',
      'Pesan pengingat WhatsApp berhasil disalin ke clipboard.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
