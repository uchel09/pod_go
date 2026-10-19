import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/printing/receipt_actions.dart';
import '../../../core/printing/receipt_data.dart';
import '../../../core/printing/receipt_data_mapper.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../routes/app_pages.dart';
import '../../pos/controllers/pos_controller.dart';
import '../sale_success_args.dart';

class SaleSuccessController extends GetxController {
  final SaleRepository _saleRepo = Get.find<SaleRepository>();

  final isLoading = true.obs;
  final saleDetail = Rxn<SaleDetail>();
  final isPrinting = false.obs;
  final isSavingPdf = false.obs;
  final autoPrintStatus = RxnString();

  SaleSuccessArgs? args;

  @override
  void onInit() {
    super.onInit();
    _initArgsAndLoad();
  }

  void _initArgsAndLoad() {
    final rawArgs = Get.arguments;
    if (rawArgs is SaleSuccessArgs) {
      args = rawArgs;
    } else if (rawArgs is int) {
      args = SaleSuccessArgs(saleId: rawArgs);
    }

    final id = args?.saleId;
    if (id != null) {
      loadSale(id);
    } else {
      isLoading.value = false;
    }

    if (args?.autoPrintJob != null) {
      _listenToAutoPrint(args!.autoPrintJob!);
    }
  }

  Future<void> _listenToAutoPrint(Future<dynamic> job) async {
    autoPrintStatus.value = 'Mencetak otomatis...';
    try {
      final res = await job;
      if (res != null && res.success == true) {
        autoPrintStatus.value = 'Struk berhasil dicetak otomatis';
      } else {
        autoPrintStatus.value = 'Cetak otomatis gagal: ${res?.error ?? "Printer tidak terhubung"}';
      }
    } catch (e) {
      autoPrintStatus.value = 'Cetak otomatis gagal: $e';
    }
  }

  Future<void> loadSale(int saleId) async {
    isLoading.value = true;
    try {
      final detail = await _saleRepo.getSaleDetail(saleId);
      saleDetail.value = detail;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat data transaksi: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  ReceiptData? get receiptData {
    final detail = saleDetail.value;
    if (detail == null) return null;
    return buildReceiptData(
      store: AuthService.to.currentStore.value,
      cashierName: detail.cashierName,
      sale: detail.sale,
      items: detail.items,
      payments: detail.payments,
    );
  }

  Future<void> printReceipt() async {
    final data = receiptData;
    if (data == null) return;

    isPrinting.value = true;
    try {
      final result = await ReceiptActions.print(data);
      if (result.success) {
        Get.snackbar(
          'Berhasil',
          'Struk berhasil dicetak.',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      isPrinting.value = false;
    }
  }

  Future<void> savePdf() async {
    final data = receiptData;
    if (data == null) return;

    isSavingPdf.value = true;
    try {
      await ReceiptActions.savePdf(data);
    } catch (e) {
      Get.snackbar('PDF', 'Gagal menyimpan / membagikan PDF: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSavingPdf.value = false;
    }
  }

  bool _isNavigating = false;

  /// Dipanggil saat layar sukses ditutup (baik via tombol maupun gesture back sistem).
  /// Mengembalikan fokus scanner / input di kasir.
  void onScreenPopped() {
    if (Get.isRegistered<PosController>()) {
      PosController.to.focusSearch();
    }
  }

  /// Menutup layar sukses dan kembali ke Kasir untuk transaksi baru.
  void newTransaction() {
    if (_isNavigating) return;
    _isNavigating = true;
    onScreenPopped();
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back();
    } else {
      Get.offNamed(Routes.POS);
    }
  }

  /// Kembali langsung ke Menu Utama (HomeView)
  void backToHome() {
    if (_isNavigating) return;
    _isNavigating = true;
    Get.offAllNamed(Routes.HOME);
  }
}
