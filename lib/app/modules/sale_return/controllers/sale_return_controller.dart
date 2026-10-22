import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/printing/receipt_actions.dart';
import '../../../core/printing/receipt_data_mapper.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/tax/tax_calculator.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/local/daos/sale_return_dao.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../data/repositories/sale_return_repository.dart';
import '../../../data/repositories/settings_repository.dart';

class ReturnableItemRow {
  final ReturnableSaleItem item;
  final RxInt returnQty;
  final RxBool restock;

  ReturnableItemRow({
    required this.item,
    int initialQty = 0,
    bool initialRestock = true,
  })  : returnQty = initialQty.obs,
        restock = initialRestock.obs;

  int get netUnitPrice {
    if (item.saleItem.qty <= 0) return item.saleItem.price;
    final netSubtotal = (item.saleItem.subtotal - item.saleItem.discountShare)
        .clamp(0, item.saleItem.subtotal);
    return netSubtotal ~/ item.saleItem.qty;
  }

  int get subtotal {
    if (item.saleItem.qty <= 0) return returnQty.value * item.saleItem.price;
    final netSubtotal = (item.saleItem.subtotal - item.saleItem.discountShare)
        .clamp(0, item.saleItem.subtotal);
    return (netSubtotal * returnQty.value) ~/ item.saleItem.qty;
  }
}

class SaleReturnController extends GetxController {
  final SaleRepository _saleRepo = Get.find<SaleRepository>();
  final SaleReturnRepository _saleReturnRepo = Get.find<SaleReturnRepository>();
  final SettingsRepository _settingsRepo = Get.find<SettingsRepository>();

  final isLoading = true.obs;
  final isSaving = false.obs;

  final saleDetail = Rxn<SaleDetail>();
  final returnableItems = <ReturnableItemRow>[].obs;
  final reasonController = TextEditingController();
  final refundMethod = 'cash'.obs; // 'cash' | 'other'

  int? saleId;

  bool get canReturn {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.posReturn);
  }

  @override
  void onInit() {
    super.onInit();
    _extractArgsAndLoad();
  }

  @override
  void onClose() {
    reasonController.dispose();
    super.onClose();
  }

  void _extractArgsAndLoad() {
    final args = Get.arguments;
    if (args is int) {
      saleId = args;
    } else if (args is Map && args['saleId'] is int) {
      saleId = args['saleId'] as int;
    }

    if (saleId != null) {
      loadSaleData(saleId!);
    } else {
      isLoading.value = false;
    }
  }

  Future<void> loadSaleData(int id) async {
    isLoading.value = true;
    try {
      final detail = await _saleRepo.getSaleDetail(id);
      if (detail == null) {
        throw const AppException('Data transaksi tidak ditemukan.');
      }
      saleDetail.value = detail;

      final items = await _saleReturnRepo.getReturnableItems(id);
      returnableItems.assignAll(
        items.map((it) => ReturnableItemRow(item: it)).toList(),
      );
    } catch (e) {
      Get.snackbar(
        'Gagal Memuat Transaksi',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
    } finally {
      isLoading.value = false;
    }
  }

  void updateQty(ReturnableItemRow row, int newQty) {
    row.returnQty.value = newQty.clamp(0, row.item.availableQty);
    returnableItems.refresh();
  }

  void toggleRestock(ReturnableItemRow row, bool val) {
    row.restock.value = val;
  }

  int get subtotalRefund =>
      returnableItems.fold<int>(0, (sum, i) => sum + i.subtotal);

  int get totalReturnedItemCount =>
      returnableItems.fold<int>(0, (sum, i) => sum + i.returnQty.value);

  int get taxRefund {
    final sale = saleDetail.value?.sale;
    if (sale == null || subtotalRefund <= 0) return 0;
    if (sale.taxRateBps != null && sale.taxRateBps! > 0 && sale.tax > 0) {
      if (sale.taxMode == 'inclusive') {
        return TaxCalculator.calculateInclusive(subtotalRefund, sale.taxRateBps!);
      } else {
        return TaxCalculator.calculateExclusive(subtotalRefund, sale.taxRateBps!);
      }
    }
    return 0;
  }

  int get totalRefund {
    final sale = saleDetail.value?.sale;
    if (sale == null) return subtotalRefund;
    if (sale.taxMode == 'exclusive') {
      return subtotalRefund + taxRefund;
    }
    return subtotalRefund;
  }

  Future<void> submitReturn() async {
    if (isSaving.value) return;

    if (!canReturn) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk memproses retur transaksi (pos.return).',
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
      return;
    }

    if (totalReturnedItemCount <= 0) {
      Get.snackbar(
        'Barang Belum Dipilih',
        'Tentukan jumlah barang yang ingin diretur terlebih dahulu.',
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
      return;
    }

    final reason = reasonController.text.trim();
    if (reason.length < 5) {
      Get.snackbar(
        'Alasan Belum Lengkap',
        'Alasan retur wajib diisi minimal 5 karakter.',
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
      return;
    }

    final confirm = await ConfirmDialog.show(
      context: Get.context!,
      title: 'Konfirmasi Retur Barang',
      message:
          'Proses retur $totalReturnedItemCount barang dengan total pengembalian uang sebesar Rp $totalRefund?\n'
          'Tindakan ini akan dicatat ke sistem dan tidak dapat dibatalkan.',
      confirmText: 'Proses Retur',
      cancelText: 'Batal',
      isDestructive: true,
    );

    if (!confirm) return;

    isSaving.value = true;
    try {
      final selectedItems = returnableItems
          .where((i) => i.returnQty.value > 0)
          .map((i) => CreateReturnItemInput(
                saleItemId: i.item.saleItem.id,
                productId: i.item.saleItem.productId,
                productName: i.item.saleItem.productName,
                qty: i.returnQty.value,
                unitPrice: i.netUnitPrice,
                costPrice: i.item.saleItem.costPrice,
                restock: i.restock.value,
              ))
          .toList();

      final deviceId = DeviceIdService.to.deviceId;
      final returnDetail = await _saleReturnRepo.createReturn(
        CreateReturnInput(
          saleId: saleDetail.value!.sale.id,
          deviceId: deviceId,
          items: selectedItems,
          refundMethod: refundMethod.value,
          reason: reason,
        ),
      );

      _showReturnSuccessDialog(returnDetail);
    } catch (e) {
      Get.snackbar(
        'Gagal Memproses Retur',
        e.toString(),
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
    } finally {
      isSaving.value = false;
    }
  }

  void _showReturnSuccessDialog(SaleReturnDetail detail) {
    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Retur Berhasil Diproses'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nomor Retur: ${detail.saleReturn.returnNo}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Nota Penjualan: ${detail.invoiceNo}'),
            const SizedBox(height: 4),
            Text('Total Pengembalian: Rp ${detail.saleReturn.total}',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Metode: ${detail.saleReturn.refundMethod.toUpperCase()}'),
            Text('Alasan: ${detail.saleReturn.reason}'),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final taxName = await _settingsRepo.getSetting('tax.name') ?? 'PPN';
              final receipt = buildReturnReceiptData(
                store: AuthService.to.currentStore.value,
                cashierName: detail.cashierName,
                saleReturn: detail.saleReturn,
                items: detail.items,
                originInvoiceNo: detail.invoiceNo,
                taxName: taxName,
              );
              await ReceiptActions.savePdf(receipt);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Simpan PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final taxName = await _settingsRepo.getSetting('tax.name') ?? 'PPN';
              final receipt = buildReturnReceiptData(
                store: AuthService.to.currentStore.value,
                cashierName: detail.cashierName,
                saleReturn: detail.saleReturn,
                items: detail.items,
                originInvoiceNo: detail.invoiceNo,
                taxName: taxName,
              );
              await ReceiptActions.print(receipt);
            },
            icon: const Icon(Icons.print),
            label: const Text('Cetak Struk'),
          ),
          FilledButton(
            onPressed: () {
              Get.back(); // close dialog
              Get.back(result: true); // return to previous screen with refreshed state
            },
            child: const Text('Selesai'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }
}
