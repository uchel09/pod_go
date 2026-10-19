import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/services/scanner/scanner_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/purchase_repository.dart';
import '../../../data/repositories/supplier_repository.dart';

class PurchaseCartItem {
  final Product product;
  final RxInt qty;
  final RxInt costPrice;
  final RxBool updateCost;

  PurchaseCartItem({
    required this.product,
    required int initialQty,
    required int initialCostPrice,
    bool initialUpdateCost = true,
  })  : qty = initialQty.obs,
        costPrice = initialCostPrice.obs,
        updateCost = initialUpdateCost.obs;

  int get subtotal => qty.value * costPrice.value;
}

class PurchaseFormController extends GetxController {
  final PurchaseRepository _purchaseRepo = Get.find<PurchaseRepository>();
  final SupplierRepository _supplierRepo = Get.find<SupplierRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  // State yang dipreservasi (Draft tidak hilang saat berpindah halaman selama app berjalan)
  static final RxList<PurchaseCartItem> draftItems = <PurchaseCartItem>[].obs;
  static final Rxn<int> draftSupplierId = Rxn<int>();
  static final RxString draftRefNo = ''.obs;
  static final Rx<DateTime> draftDate = DateTime.now().obs;
  static final RxBool draftUpdateCostPrice = true.obs;

  final suppliers = <Supplier>[].obs;
  final allProducts = <Product>[].obs;
  final isSaving = false.obs;
  final isLoadingSuppliers = false.obs;

  final refNoController = TextEditingController();

  RxList<PurchaseCartItem> get items => draftItems;
  Rxn<int> get selectedSupplierId => draftSupplierId;
  Rx<DateTime> get purchaseDate => draftDate;
  RxBool get updateCostPrice => draftUpdateCostPrice;

  int get totalAmount => items.fold<int>(0, (sum, it) => sum + it.subtotal);
  int get totalItemCount => items.fold<int>(0, (sum, it) => sum + it.qty.value);

  bool get canPurchase => PermissionService.to.can(PermissionKeys.stockPurchase);

  @override
  void onInit() {
    super.onInit();
    // Validasi Gate Lisensi & Hak Akses
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.purchases)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FeatureGate.to.requireFeature(Feature.purchases);
        });
        return;
      }
    }

    refNoController.text = draftRefNo.value;
    refNoController.addListener(() {
      draftRefNo.value = refNoController.text;
    });

    loadInitialData();

    // Register Scanner HID Consumer
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.registerConsumer('purchase_form', handleScannedBarcode);
    }
  }

  @override
  void onClose() {
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.unregisterConsumer('purchase_form');
    }
    refNoController.dispose();
    super.onClose();
  }

  Future<void> loadInitialData() async {
    isLoadingSuppliers.value = true;
    try {
      suppliers.value = await _supplierRepo.getAllSuppliers();
      allProducts.value = await _productRepo.getAllProducts();
    } catch (_) {
    } finally {
      isLoadingSuppliers.value = false;
    }
  }

  void handleScannedBarcode(String barcode) async {
    await addProductByBarcode(barcode);
  }

  Future<void> scanWithCamera() async {
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
    // 1. Cek produk nonaktif
    if (!product.isActive) {
      Get.snackbar(
        'Produk Nonaktif',
        'Produk "${product.name}" sedang nonaktif dan tidak dapat ditambahkan ke pembelian.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.amber.shade100,
      );
      return;
    }

    // 2. Cek produk terkunci tier
    final isLocked = await _productRepo.isProductLockedByTier(product);
    if (isLocked) {
      Get.snackbar(
        'Produk Terkunci',
        'Produk "${product.name}" terkunci oleh kuota tier lisensi dan tidak dapat ditambahkan ke pembelian.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.amber.shade100,
      );
      return;
    }

    // 3. Masukkan ke cart atau tambahkan qty
    final existingIdx = items.indexWhere((it) => it.product.id == product.id);
    if (existingIdx != -1) {
      items[existingIdx].qty.value += 1;
      Get.snackbar(
        'Jumlah Ditambah (+1)',
        '${product.name} (Total: ${items[existingIdx].qty.value})',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
    } else {
      items.add(
        PurchaseCartItem(
          product: product,
          initialQty: 1,
          initialCostPrice: product.costPrice,
          initialUpdateCost: true,
        ),
      );
      Get.snackbar(
        'Produk Ditambahkan',
        product.name,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
    }
  }

  void updateItemQty(PurchaseCartItem item, int newQty) {
    if (newQty <= 0) {
      removeItem(item);
    } else {
      item.qty.value = newQty;
    }
  }

  void updateItemCostPrice(PurchaseCartItem item, int newCostPrice) {
    if (newCostPrice < 0) return;
    item.costPrice.value = newCostPrice;
  }

  void removeItem(PurchaseCartItem item) {
    items.remove(item);
  }

  void clearDraft() {
    items.clear();
    draftSupplierId.value = null;
    draftRefNo.value = '';
    refNoController.clear();
    draftDate.value = DateTime.now();
    draftUpdateCostPrice.value = true;
  }

  /// Menghitung daftar produk yang akan mengalami perubahan harga beli jika disimpan
  List<Map<String, dynamic>> getCostPriceChanges() {
    final changes = <Map<String, dynamic>>[];
    for (final it in items) {
      if (updateCostPrice.value && it.updateCost.value && it.costPrice.value != it.product.costPrice) {
        changes.add({
          'name': it.product.name,
          'oldCost': it.product.costPrice,
          'newCost': it.costPrice.value,
          'diff': it.costPrice.value - it.product.costPrice,
        });
      }
    }
    return changes;
  }

  /// Simpan transaksi pembelian ke repository
  Future<bool> savePurchase() async {
    if (isSaving.value) return false;

    if (items.isEmpty) {
      Get.snackbar('Validasi Gagal', 'Daftar barang pembelian masih kosong.');
      return false;
    }

    isSaving.value = true;
    try {
      final inputItems = items.map((it) {
        return PurchaseItemInput(
          productId: it.product.id,
          qty: it.qty.value,
          costPrice: it.costPrice.value,
          updateProductCost: it.updateCost.value,
        );
      }).toList();

      final purchase = await _purchaseRepo.receive(
        supplierId: selectedSupplierId.value,
        refNo: refNoController.text.trim().isEmpty ? null : refNoController.text.trim(),
        date: purchaseDate.value,
        items: inputItems,
        updateCostPrice: updateCostPrice.value,
      );

      // Bersihkan draft setelah berhasil
      clearDraft();

      Get.back(); // Kembali ke daftar pembelian
      Get.snackbar(
        'Sukses Menyimpan Pembelian',
        'Faktur ${purchase.refNo} berhasil dicatat dan stok barang telah bertambah.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade900,
      );
      return true;
    } on AppException catch (e) {
      e.showSnackbar();
      return false;
    } catch (e) {
      Get.snackbar('Error', 'Gagal menyimpan transaksi pembelian: $e');
      return false;
    } finally {
      isSaving.value = false;
    }
  }
}
