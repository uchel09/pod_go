import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/services/pdf/opname_pdf_service.dart';
import '../../../core/services/scanner/scanner_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/opname_dao.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/opname_repository.dart';
import '../../../data/repositories/product_repository.dart';

class OpnameDetailController extends GetxController {
  final OpnameRepository _opnameRepo = Get.find<OpnameRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final CategoryRepository _categoryRepo = Get.find<CategoryRepository>();

  late int opnameId;

  final detail = Rxn<OpnameDetailEntry>();
  final isLoading = true.obs;
  final isSaving = false.obs;

  final searchQuery = ''.obs;
  final filterStatus = 'all'.obs; // 'all', 'uncounted', 'counted', 'diff'

  final categories = <Category>[].obs;
  final allProducts = <Product>[].obs;

  bool get canManage => PermissionService.to.can(PermissionKeys.stockOpname);
  bool get canViewCost => PermissionService.to.can(PermissionKeys.productViewCost);
  bool get hasFeature => FeatureGate.to.isEnabled(Feature.stockOpname);

  bool get isDraft => detail.value?.isDraft ?? true;
  bool get isFinal => detail.value?.isFinal ?? false;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['opnameId'] != null) {
      opnameId = args['opnameId'] as int;
    } else {
      opnameId = int.tryParse(Get.parameters['id'] ?? '0') ?? 0;
    }

    loadInitialData();

    // Register HID Scanner
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.registerConsumer('stock_opname_detail', handleScannedBarcode);
    }
  }

  @override
  void onClose() {
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.unregisterConsumer('stock_opname_detail');
    }
    super.onClose();
  }

  Future<void> loadInitialData() async {
    isLoading.value = true;
    try {
      categories.value = await _categoryRepo.getAllCategories();
      allProducts.value = await _productRepo.getAllProducts();
      await loadDetail();
    } catch (e) {
      Get.snackbar('Gagal Memuat Data', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadDetail() async {
    try {
      final res = await _opnameRepo.getOpnameDetail(opnameId);
      if (res == null) {
        Get.snackbar('Error', 'Sesi opname tidak ditemukan', snackPosition: SnackPosition.BOTTOM);
        Get.back();
        return;
      }
      detail.value = res;
    } catch (e) {
      Get.snackbar('Gagal Memuat Sesi Opname', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  void handleScannedBarcode(String barcode) async {
    if (!isDraft) return;
    await addProductByBarcode(barcode);
  }

  Future<void> scanWithCamera() async {
    if (!isDraft) return;
    if (Get.isRegistered<ScannerService>()) {
      final code = await ScannerService.to.scanWithCamera();
      if (code != null && code.isNotEmpty) {
        await addProductByBarcode(code);
      }
    }
  }

  Future<void> addProductByBarcode(String barcode) async {
    final cleaned = barcode.trim();
    if (cleaned.isEmpty) return;

    final product = await _productRepo.getProductByBarcodeOrInternalCode(cleaned);
    if (product == null) {
      Get.snackbar(
        'Produk Tidak Ditemukan',
        'Tidak ada produk dengan barcode atau kode "$cleaned"',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await addProduct(product);
  }

  Future<void> addProduct(Product product) async {
    if (!isDraft) return;

    try {
      await _opnameRepo.addOrIncrementItem(
        opnameId: opnameId,
        productId: product.id,
        qty: 1,
      );
      await loadDetail();

      Get.snackbar(
        'Hitungan Ditambahkan',
        '${product.name} berhasil dihitung (+1)',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
    } catch (e) {
      Get.snackbar('Gagal Menambah Hitungan', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> incrementCount(OpnameItemWithProduct item) async {
    if (!isDraft) return;
    try {
      final nextCount = item.isCounted ? item.countedQty + 1 : 1;
      await _opnameRepo.updateItemCount(
        opnameId: opnameId,
        itemId: item.id,
        countedQty: nextCount,
      );
      await loadDetail();
    } catch (e) {
      Get.snackbar('Gagal Mengubah Hitungan', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> decrementCount(OpnameItemWithProduct item) async {
    if (!isDraft) return;
    if (!item.isCounted || item.countedQty <= 0) return;

    try {
      final nextCount = item.countedQty - 1;
      await _opnameRepo.updateItemCount(
        opnameId: opnameId,
        itemId: item.id,
        countedQty: nextCount,
      );
      await loadDetail();
    } catch (e) {
      Get.snackbar('Gagal Mengubah Hitungan', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> setCountDirectly(OpnameItemWithProduct item, int count) async {
    if (!isDraft) return;
    if (count < 0) return;

    try {
      await _opnameRepo.updateItemCount(
        opnameId: opnameId,
        itemId: item.id,
        countedQty: count,
      );
      await loadDetail();
    } catch (e) {
      Get.snackbar('Gagal Mengubah Hitungan', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> removeItem(OpnameItemWithProduct item) async {
    if (!isDraft) return;

    try {
      await _opnameRepo.deleteItem(opnameId: opnameId, itemId: item.id);
      await loadDetail();
    } catch (e) {
      Get.snackbar('Gagal Menghapus Item', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> loadAllActiveProducts() async {
    if (!isDraft) return;

    isLoading.value = true;
    try {
      final addedCount = await _opnameRepo.loadAllActiveProducts(opnameId);
      await loadDetail();
      Get.snackbar(
        'Produk Dimuat',
        '$addedCount produk aktif berhasil ditambahkan ke sesi hitung.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Gagal Memuat Semua Produk', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadProductsByCategory(int categoryId) async {
    if (!isDraft) return;

    isLoading.value = true;
    try {
      final addedCount = await _opnameRepo.loadProductsByCategory(
        opnameId: opnameId,
        categoryId: categoryId,
      );
      await loadDetail();
      Get.snackbar(
        'Produk Kategori Dimuat',
        '$addedCount produk berhasil ditambahkan ke sesi hitung.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Gagal Memuat Produk Kategori', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  /// Menyiapkan data review dengan menghitung ulang systemQty dari stok terkini
  Future<OpnameDetailEntry?> prepareReview() async {
    try {
      return await _opnameRepo.recalculateReview(opnameId);
    } catch (e) {
      Get.snackbar('Gagal Menghitung Ulang Review', e.toString(), snackPosition: SnackPosition.BOTTOM);
      return null;
    }
  }

  /// Eksekusi finalisasi stock opname secara atomik
  Future<bool> executeFinalize({
    required bool treatUncountedAsZero,
    String? note,
  }) async {
    if (isSaving.value) return false;
    isSaving.value = true;

    try {
      await _opnameRepo.finalize(
        opnameId: opnameId,
        treatUncountedAsZero: treatUncountedAsZero,
        note: note,
      );
      await loadDetail();
      Get.snackbar(
        'Stock Opname Selesai',
        'Stok seluruh produk telah disesuaikan dan sesi telah difinalisasi.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
      );
      return true;
    } catch (e) {
      Get.snackbar(
        'Gagal Memfinalisasi',
        e is AppException ? e.message : e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> deleteDraft() async {
    if (!isDraft) return;

    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Hapus Draft Opname?'),
        content: const Text(
          'Sesi ini beserta seluruh data hitungan fisik akan dihapus permanen dari sistem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _opnameRepo.deleteOpname(opnameId);
      Get.back();
      Get.snackbar('Draft Dihapus', 'Sesi stock opname telah dihapus.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Gagal Menghapus', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> printReport() async {
    if (detail.value == null) return;
    try {
      final store = AuthService.to.currentStore.value;
      final pdfBytes = await OpnamePdfService.generateOpnameReport(
        store: store,
        detail: detail.value!,
        canViewCost: canViewCost,
      );

      await Printing.layoutPdf(
        name: 'Opname_${detail.value!.code}.pdf',
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      Get.snackbar('Gagal Mencetak', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> shareReportPdf() async {
    if (detail.value == null) return;
    try {
      final store = AuthService.to.currentStore.value;
      final pdfBytes = await OpnamePdfService.generateOpnameReport(
        store: store,
        detail: detail.value!,
        canViewCost: canViewCost,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Opname_${detail.value!.code}.pdf',
      );
    } catch (e) {
      Get.snackbar('Gagal Membagikan PDF', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Filter item berdasarkan teks pencarian dan filter status (belum/sudah/selisih)
  List<OpnameItemWithProduct> get filteredItems {
    final entry = detail.value;
    if (entry == null) return [];

    var list = entry.items;

    // Filter status
    switch (filterStatus.value) {
      case 'uncounted':
        list = list.where((i) => !i.isCounted).toList();
        break;
      case 'counted':
        list = list.where((i) => i.isCounted).toList();
        break;
      case 'diff':
        list = list.where((i) => i.isCounted && i.difference != 0).toList();
        break;
      case 'all':
      default:
        break;
    }

    // Filter search query
    if (searchQuery.value.trim().isNotEmpty) {
      final q = searchQuery.value.trim().toLowerCase();
      list = list.where((i) {
        final name = i.product.name.toLowerCase();
        final barcode = i.product.barcode?.toLowerCase() ?? '';
        final internal = i.product.internalCode?.toLowerCase() ?? '';
        return name.contains(q) || barcode.contains(q) || internal.contains(q);
      }).toList();
    }

    return list;
  }
}
