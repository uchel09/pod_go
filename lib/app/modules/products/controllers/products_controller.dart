import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Value;

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/services/scanner/scanner_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../routes/app_pages.dart';

class ProductsController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final CategoryRepository _categoryRepo = Get.find<CategoryRepository>();
  final UnitRepository _unitRepo = Get.find<UnitRepository>();
  final StockRepository _stockRepo = Get.find<StockRepository>();

  final allProducts = <Product>[].obs;
  final categories = <Category>[].obs;
  final units = <Unit>[].obs;
  final activeCount = 0.obs;

  final searchQuery = ''.obs;
  final selectedCategoryId = Rxn<int>();
  final selectedStatusFilter = 'all'.obs; // 'all' | 'active' | 'inactive' | 'low_stock'
  final isLoading = true.obs;
  final searchController = TextEditingController();

  // Permissions & Tier
  bool get canEdit => PermissionService.to.can(PermissionKeys.productEdit);
  bool get canView => PermissionService.to.can(PermissionKeys.productView);
  bool get canViewCost => PermissionService.to.can(PermissionKeys.productViewCost);
  bool get canEditPrice => PermissionService.to.can(PermissionKeys.productEditPrice);

  int? get tierLimit => FeatureGate.to.productLimit;

  String get addButtonLabel {
    final limit = tierLimit;
    if (limit != null) {
      return 'Tambah (${activeCount.value}/$limit)';
    }
    return 'Tambah Produk';
  }

  @override
  void onInit() {
    super.onInit();
    _bindStreams();
    _loadInitialData();
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.registerConsumer('products', (code) {
        searchController.text = code;
        updateSearch(code);
      });
    }
  }

  Future<void> _loadInitialData() async {
    try {
      final list = await _productRepo.getAllProducts();
      if (allProducts.isEmpty && list.isNotEmpty) {
        allProducts.assignAll(list);
      }
      isLoading.value = false;
    } catch (_) {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.unregisterConsumer('products');
    }
    searchController.dispose();
    super.onClose();
  }

  void _bindStreams() {
    allProducts.bindStream(
      _productRepo.watchAllProducts().handleError((err) {
        isLoading.value = false;
      }).map((list) {
        isLoading.value = false;
        return list;
      }),
    );

    categories.bindStream(_categoryRepo.watchAllCategories());
    units.bindStream(_unitRepo.watchAllUnits());

    activeCount.bindStream(_productRepo.watchActiveProductsCount());
  }

  /// Kumpulan ID produk yang terkunci (read-only) karena tier lisensi turun
  Set<int> get lockedProductIds {
    final limit = tierLimit;
    if (limit == null) return {};

    final activeSorted = allProducts.where((p) => p.isActive).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (activeSorted.length <= limit) return {};
    return activeSorted.skip(limit).map((p) => p.id).toSet();
  }

  bool isProductLocked(Product product) {
    return lockedProductIds.contains(product.id);
  }

  /// Daftar produk yang telah difilter berdasarkan pencarian, kategori, dan status
  List<Product> get filteredProducts {
    var list = allProducts.toList();

    // 1. Filter Pencarian (nama, sku, barcode, internalCode)
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((p) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
        final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
        final internalMatch = p.internalCode?.toLowerCase().contains(query) ?? false;
        return nameMatch || skuMatch || barcodeMatch || internalMatch;
      }).toList();
    }

    // 2. Filter Kategori
    if (selectedCategoryId.value != null) {
      list = list.where((p) => p.categoryId == selectedCategoryId.value).toList();
    }

    // 3. Filter Status (all, active, inactive, low_stock)
    switch (selectedStatusFilter.value) {
      case 'active':
        list = list.where((p) => p.isActive).toList();
        break;
      case 'inactive':
        list = list.where((p) => !p.isActive).toList();
        break;
      case 'low_stock':
        list = list.where((p) => p.currentStock <= p.minStock).toList();
        break;
      case 'all':
      default:
        break;
    }

    return list;
  }

  void updateSearch(String query) {
    searchQuery.value = query;
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }

  void filterByCategory(int? categoryId) {
    selectedCategoryId.value = categoryId;
  }

  void filterByStatus(String status) {
    selectedStatusFilter.value = status;
  }

  String getCategoryName(int? categoryId) {
    if (categoryId == null) return '-';
    final cat = categories.firstWhereOrNull((c) => c.id == categoryId);
    return cat?.name ?? '-';
  }

  String getUnitSymbol(int? unitId) {
    if (unitId == null) return '';
    final u = units.firstWhereOrNull((item) => item.id == unitId);
    return u?.symbol ?? '';
  }

  /// Membuat kode internal unik
  Future<Map<String, String>> generateInternalCode() async {
    return _productRepo.generateInternalCode();
  }

  /// Simpan produk baru (Create)
  Future<int> addProduct({
    required String name,
    required int sellPrice,
    int costPrice = 0,
    int initialStock = 0,
    int minStock = 0,
    int? categoryId,
    int? unitId,
    String? sku,
    String? barcode,
    String? internalCode,
    String codeType = 'manufacturer',
  }) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin menambah produk.');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException('Nama produk wajib diisi.');
    }
    if (sellPrice < 0) {
      throw const AppException('Harga jual tidak boleh kurang dari 0.');
    }
    if (costPrice < 0) {
      throw const AppException('Harga beli tidak boleh kurang dari 0.');
    }
    if (minStock < 0) {
      throw const AppException('Stok minimum tidak boleh kurang dari 0.');
    }

    final trimmedBarcode = barcode?.trim().isEmpty ?? true ? null : barcode!.trim();
    final trimmedInternalCode = internalCode?.trim().isEmpty ?? true ? null : internalCode!.trim();
    final trimmedSku = sku?.trim().isEmpty ?? true ? null : sku!.trim();

    // Verifikasi keunikan barcode jika diisi
    if (trimmedBarcode != null) {
      final existing = await _productRepo.getProductByBarcode(trimmedBarcode);
      if (existing != null) {
        throw AppException(
          'Barcode "$trimmedBarcode" sudah digunakan oleh produk "${existing.name}".',
          code: 'BARCODE_DUPLICATE',
        );
      }
    }

    final companion = ProductsCompanion(
      name: Value(trimmedName),
      categoryId: Value(categoryId),
      unitId: Value(unitId),
      costPrice: Value(costPrice),
      sellPrice: Value(sellPrice),
      minStock: Value(minStock),
      currentStock: const Value(0), // Diisi via StockRepository.applyMovement jika ada stok awal
      sku: Value(trimmedSku),
      barcode: Value(trimmedBarcode),
      internalCode: Value(trimmedInternalCode),
      codeType: Value(codeType),
      isActive: const Value(true),
    );

    int newId;
    try {
      newId = await _productRepo.createProduct(companion);
    } on LimitReachedException catch (e) {
      _showUpgradePrompt(e.message);
      rethrow;
    }

    // Catat stok awal sebagai stock_movement type adjustment
    if (initialStock > 0) {
      final currentUserId = AuthService.to.currentUser.value?.id;
      await _stockRepo.applyMovement(
        productId: newId,
        type: 'adjustment',
        qtyChange: initialStock,
        note: 'Stok awal produk baru',
        createdBy: currentUserId,
      );
    }

    // Log audit
    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'product.create',
        entity: 'products',
        entityId: newId,
        detail: {
          'name': trimmedName,
          'sellPrice': sellPrice,
          'costPrice': costPrice,
          'initialStock': initialStock,
          'barcode': trimmedBarcode,
        },
      );
    }

    // Segera sinkronkan produk baru ke allProducts agar langsung tampil
    final createdProduct = await _productRepo.getProductById(newId);
    if (createdProduct != null) {
      final idx = allProducts.indexWhere((p) => p.id == newId);
      if (idx == -1) {
        allProducts.add(createdProduct);
      } else {
        allProducts[idx] = createdProduct;
      }
    }

    return newId;
  }

  /// Ubah data produk (Update)
  Future<void> updateProductData({
    required Product oldProduct,
    required String name,
    required int sellPrice,
    int costPrice = 0,
    int minStock = 0,
    int? categoryId,
    int? unitId,
    String? sku,
    String? barcode,
    String? internalCode,
    String codeType = 'manufacturer',
    String stockActionMode = 'keep', // 'keep' | 'add' | 'set'
    int stockDelta = 0,
    String? stockNote,
  }) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengedit produk.');
    }

    if (isProductLocked(oldProduct)) {
      throw const AppException(
        'Produk ini terkunci oleh batas tier lisensi. Silakan upgrade atau nonaktifkan produk lain terlebih dahulu.',
        code: 'PRODUCT_LOCKED_BY_TIER',
      );
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException('Nama produk wajib diisi.');
    }
    if (sellPrice < 0) {
      throw const AppException('Harga jual tidak boleh kurang dari 0.');
    }
    if (costPrice < 0) {
      throw const AppException('Harga beli tidak boleh kurang dari 0.');
    }
    if (minStock < 0) {
      throw const AppException('Stok minimum tidak boleh kurang dari 0.');
    }

    final trimmedBarcode = barcode?.trim().isEmpty ?? true ? null : barcode!.trim();
    final trimmedInternalCode = internalCode?.trim().isEmpty ?? true ? null : internalCode!.trim();
    final trimmedSku = sku?.trim().isEmpty ?? true ? null : sku!.trim();

    // Verifikasi keunikan barcode bila diubah
    if (trimmedBarcode != null && trimmedBarcode != oldProduct.barcode) {
      final existing = await _productRepo.getProductByBarcode(trimmedBarcode);
      if (existing != null && existing.id != oldProduct.id) {
        throw AppException(
          'Barcode "$trimmedBarcode" sudah digunakan oleh produk "${existing.name}".',
          code: 'BARCODE_DUPLICATE',
        );
      }
    }

    final companion = ProductsCompanion(
      id: Value(oldProduct.id),
      name: Value(trimmedName),
      categoryId: Value(categoryId),
      unitId: Value(unitId),
      costPrice: Value(costPrice),
      sellPrice: Value(sellPrice),
      minStock: Value(minStock),
      currentStock: Value(oldProduct.currentStock),
      sku: Value(trimmedSku),
      barcode: Value(trimmedBarcode),
      internalCode: Value(trimmedInternalCode),
      codeType: Value(codeType),
      isActive: Value(oldProduct.isActive),
      createdAt: Value(oldProduct.createdAt),
      updatedAt: Value(DateTime.now()),
    );

    await _productRepo.updateProduct(companion);

    // Proses perubahan stok jika dipilih (Tambah Stok atau Edit/Set Stok)
    if (stockActionMode != 'keep' && stockDelta != 0) {
      final currentUserId = AuthService.to.currentUser.value?.id;
      final defaultNote = stockActionMode == 'add' ? 'Tambah stok produk' : 'Koreksi penyesuaian stok';
      final appliedNote = (stockNote != null && stockNote.trim().isNotEmpty) ? stockNote.trim() : defaultNote;

      await _stockRepo.applyMovement(
        productId: oldProduct.id,
        type: 'adjustment',
        qtyChange: stockDelta,
        note: appliedNote,
        createdBy: currentUserId,
      );

      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'stock.adjustment',
          entity: 'products',
          entityId: oldProduct.id,
          detail: {
            'productName': trimmedName,
            'oldStock': oldProduct.currentStock,
            'newStock': oldProduct.currentStock + stockDelta,
            'qtyChange': stockDelta,
            'mode': stockActionMode,
            'note': appliedNote,
          },
        );
      }
    }

    // Sinkronkan produk ke allProducts
    final updated = await _productRepo.getProductById(oldProduct.id);
    if (updated != null) {
      final idx = allProducts.indexWhere((p) => p.id == oldProduct.id);
      if (idx != -1) {
        allProducts[idx] = updated;
      }
    }

    // Audit log jika terjadi perubahan harga
    if (oldProduct.sellPrice != sellPrice || oldProduct.costPrice != costPrice) {
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'product.price_change',
          entity: 'products',
          entityId: oldProduct.id,
          detail: {
            'productName': trimmedName,
            'oldCostPrice': oldProduct.costPrice,
            'newCostPrice': costPrice,
            'oldSellPrice': oldProduct.sellPrice,
            'newSellPrice': sellPrice,
          },
        );
      }
    } else {
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'product.update',
          entity: 'products',
          entityId: oldProduct.id,
          detail: {'name': trimmedName},
        );
      }
    }
  }

  /// Penyesuaian stok langsung (Direct Stock Adjustment)
  Future<void> adjustStock({
    required Product product,
    required String mode, // 'add' | 'set'
    required int qty,
    String? note,
  }) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengubah stok.');
    }

    if (isProductLocked(product)) {
      throw const AppException(
        'Produk ini terkunci oleh batas tier lisensi.',
        code: 'PRODUCT_LOCKED_BY_TIER',
      );
    }

    final int qtyChange = mode == 'add' ? qty : (qty - product.currentStock);
    if (qtyChange == 0) return;

    if (product.currentStock + qtyChange < 0) {
      throw const AppException('Stok produk tidak boleh menjadi negatif.');
    }

    final currentUserId = AuthService.to.currentUser.value?.id;
    final defaultNote = mode == 'add' ? 'Tambah stok produk' : 'Koreksi stok produk';
    final appliedNote = (note != null && note.trim().isNotEmpty) ? note.trim() : defaultNote;

    await _stockRepo.applyMovement(
      productId: product.id,
      type: 'adjustment',
      qtyChange: qtyChange,
      note: appliedNote,
      createdBy: currentUserId,
    );

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'stock.adjustment',
        entity: 'products',
        entityId: product.id,
        detail: {
          'productName': product.name,
          'oldStock': product.currentStock,
          'newStock': product.currentStock + qtyChange,
          'qtyChange': qtyChange,
          'mode': mode,
          'note': appliedNote,
        },
      );
    }

    final updated = await _productRepo.getProductById(product.id);
    if (updated != null) {
      final idx = allProducts.indexWhere((p) => p.id == product.id);
      if (idx != -1) {
        allProducts[idx] = updated;
      }
    }
  }

  /// Toggle status aktif/nonaktif produk
  Future<void> toggleProductActive(Product product) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengubah status produk.');
    }

    final newStatus = !product.isActive;

    // Jika ingin mengaktifkan kembali, periksa kuota tier
    if (newStatus) {
      final limit = tierLimit;
      if (limit != null) {
        final currentActive = await _productRepo.countActiveProducts();
        if (currentActive >= limit) {
          _showUpgradePrompt(
            'Batas maksimal $limit produk aktif telah tercapai pada tier Gratis.\n\nSilakan upgrade ke Semi-Premium atau nonaktifkan produk lain.',
          );
          throw LimitReachedException(
            'Batas maksimal $limit produk aktif telah tercapai.',
            limit: limit,
          );
        }
      }
    }

    await _productRepo.setProductActive(product.id, newStatus);
    final idx = allProducts.indexWhere((p) => p.id == product.id);
    if (idx != -1) {
      allProducts[idx] = product.copyWith(isActive: newStatus, updatedAt: DateTime.now());
    }

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: newStatus ? 'product.activate' : 'product.deactivate',
        entity: 'products',
        entityId: product.id,
        detail: {'name': product.name},
      );
    }

    Get.snackbar(
      'Status Diperbarui',
      'Produk "${product.name}" sekarang ${newStatus ? "Aktif" : "Nonaktif"}',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Menghapus produk (hanya bila belum pernah digunakan)
  Future<void> deleteProduct(Product product) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin menghapus produk.');
    }

    // Periksa riwayat mutasi stok
    final movements = await _stockRepo.getMovementsByProduct(product.id);
    if (movements.isNotEmpty) {
      throw const AppException(
        'Produk ini memiliki riwayat stok / transaksi dan tidak dapat dihapus permanen.\n\nSilakan nonaktifkan produk ini sebagai gantinya.',
        code: 'PRODUCT_HAS_HISTORY',
      );
    }

    await _productRepo.deleteProduct(product.id);
    allProducts.removeWhere((p) => p.id == product.id);

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'product.delete',
        entity: 'products',
        entityId: product.id,
        detail: {'name': product.name},
      );
    }
  }

  void _showUpgradePrompt(String message) {
    Get.snackbar(
      'Batas Produk Tercapai',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () => Get.toNamed(Routes.UPGRADE, arguments: {'feature': Feature.unlimitedProducts}),
        child: const Text('UPGRADE', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// Dialog konfirmasi hapus / nonaktifkan
  void confirmDeleteProduct(BuildContext context, Product product) async {
    if (!canEdit) return;

    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Hapus Produk',
      message: 'Apakah Anda yakin ingin menghapus produk "${product.name}"?',
      confirmText: 'Hapus',
      isDestructive: true,
    );

    if (!confirmed) return;

    try {
      await deleteProduct(product);
      Get.snackbar(
        'Sukses',
        'Produk "${product.name}" berhasil dihapus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      e.showSnackbar();
    } catch (e) {
      Get.snackbar('Error', 'Gagal menghapus produk: $e');
    }
  }

  /// Membuka form tambah produk (memeriksa kuota tier terlebih dahulu)
  void onAddProductPressed(BuildContext context) {
    if (!canEdit) {
      Get.snackbar('Akses Ditolak', 'Anda tidak memiliki hak akses mengedit produk.');
      return;
    }

    final limit = tierLimit;
    if (limit != null && activeCount.value >= limit) {
      _showUpgradePrompt(
        'Kuota $limit produk aktif di tier Gratis sudah penuh (7/10).\n\nUpgrade ke Semi-Premium untuk menikmati produk tanpa batas.',
      );
      Get.toNamed(Routes.UPGRADE, arguments: {'feature': Feature.unlimitedProducts});
      return;
    }

    showProductFormDialog(context: context);
  }

  /// Menampilkan Form Tambah / Edit Produk
  void showProductFormDialog({
    required BuildContext context,
    Product? productToEdit,
  }) {
    if (!canEdit) return;

    final isEdit = productToEdit != null;

    if (isEdit && isProductLocked(productToEdit)) {
      Get.snackbar(
        'Produk Terkunci',
        'Produk ini berstatus read-only karena berada di luar kuota tier Gratis saat ini.\nSilakan upgrade lisensi untuk mengeditnya.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final nameController = TextEditingController(text: productToEdit?.name ?? '');
    final sellPriceController = TextEditingController(
      text: productToEdit != null ? productToEdit.sellPrice.toString() : '',
    );
    final costPriceController = TextEditingController(
      text: productToEdit != null ? productToEdit.costPrice.toString() : '0',
    );
    final initialStockController = TextEditingController(text: '0');
    final minStockController = TextEditingController(
      text: productToEdit != null ? productToEdit.minStock.toString() : '5',
    );
    final skuController = TextEditingController(text: productToEdit?.sku ?? '');
    final barcodeController = TextEditingController(text: productToEdit?.barcode ?? '');
    final internalCodeController = TextEditingController(text: productToEdit?.internalCode ?? '');

    // State manajemen stok saat edit produk
    final RxString stockActionMode = 'keep'.obs; // 'keep' | 'add' | 'set'
    final addStockController = TextEditingController(text: '0');
    final setStockController = TextEditingController(
      text: productToEdit != null ? productToEdit.currentStock.toString() : '0',
    );
    final stockNoteController = TextEditingController();

    final Rx<String> selectedCodeType = (productToEdit?.codeType ?? 'manufacturer').obs;
    final Rxn<int> selectedCat = Rxn<int>(productToEdit?.categoryId);
    final Rxn<int> selectedUnit = Rxn<int>(productToEdit?.unitId);

    // Default jika belum dipilih: pilih yang pertama jika ada
    if (selectedCat.value == null && categories.isNotEmpty) {
      selectedCat.value = categories.first.id;
    }
    if (selectedUnit.value == null && units.isNotEmpty) {
      selectedUnit.value = units.first.id;
    }

    // Daftarkan dialog produk sebagai consumer aktif scanner
    if (Get.isRegistered<ScannerService>()) {
      ScannerService.to.registerConsumer('product_form', (scannedCode) {
        barcodeController.text = scannedCode;
        Get.snackbar(
          'Barcode Terpindai',
          'Kode "$scannedCode" dimasukkan ke field barcode.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );
      });
    }

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final isTablet = screenSize.width >= 600 && screenSize.width < 960;

    Get.dialog(
      Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : (isTablet ? 24 : 40),
          vertical: isMobile ? 12 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 650,
            maxHeight: screenSize.height * (isMobile ? 0.94 : 0.88),
          ),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: isMobile ? 18 : 22,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        isEdit ? Icons.edit_note : Icons.add_box_outlined,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: isMobile ? 20 : 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit Produk' : 'Tambah Produk Baru',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 18 : 20,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            isEdit
                                ? 'Perbarui informasi, harga & stok produk'
                                : 'Lengkapi data master produk toko Anda',
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Form Scrollable
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tip Singkat Barcode
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lightbulb_outline, color: Colors.amber.shade800, size: 18),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Tip: Barang kemasan pabrik cukup daftarkan barcode aslinya.',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Nama Produk
                        TextField(
                          controller: nameController,
                          autofocus: !isEdit,
                          decoration: const InputDecoration(
                            labelText: 'Nama Produk *',
                            hintText: 'Misal: Kopi Susu Gula Aren 250ml',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 14),

                        // Kategori & Satuan Dropdown (Responsif: Vertikal di Mobile, Horizontal di Tablet/Desktop)
                        Obx(() {
                          final categoryDropdown = DropdownButtonFormField<int>(
                            initialValue: selectedCat.value,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kategori',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: categories.map((cat) {
                              return DropdownMenuItem<int>(
                                value: cat.id,
                                child: Text(cat.name, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) => selectedCat.value = val,
                          );

                          final unitDropdown = DropdownButtonFormField<int>(
                            initialValue: selectedUnit.value,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Satuan',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: units.map((u) {
                              return DropdownMenuItem<int>(
                                value: u.id,
                                child: Text('${u.name} (${u.symbol})', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) => selectedUnit.value = val,
                          );

                          if (isMobile) {
                            return Column(
                              children: [
                                categoryDropdown,
                                const SizedBox(height: 12),
                                unitDropdown,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: categoryDropdown),
                              const SizedBox(width: 12),
                              Expanded(child: unitDropdown),
                            ],
                          );
                        }),
                        const SizedBox(height: 14),

                        // Bagian Kode & Barcode (Dua Jalur)
                        Text(
                          'Pendaftaran Kode & Barcode',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: barcodeController,
                          decoration: InputDecoration(
                            labelText: 'Barcode / Kode Produk',
                            hintText: 'Ketik atau buat kode otomatis',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.qr_code_2),
                            suffixIcon: (Get.isRegistered<ScannerService>() && ScannerService.to.isCameraSupported)
                                ? IconButton(
                                    tooltip: 'Scan Barcode Kamera (Android)',
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    onPressed: () async {
                                      final code = await ScannerService.to.scanWithCamera();
                                      if (code != null && code.isNotEmpty) {
                                        barcodeController.text = code;
                                      }
                                    },
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Wrap generator button & chip agar tidak pernah overflow
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final res = await generateInternalCode();
                                barcodeController.text = res['code']!;
                                internalCodeController.text = res['code']!;
                                selectedCodeType.value = res['codeType']!;
                                Get.snackbar(
                                  'Kode Internal Dibuat',
                                  'Kode ${res['code']} berhasil di-generate (${res['codeType']})',
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              },
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: Text(isMobile ? 'Kode Otomatis (P+6)' : 'Buat Kode Internal (P+6 digit)'),
                            ),
                            Obx(() => Chip(
                                  label: Text(
                                    selectedCodeType.value == 'manufacturer'
                                        ? 'Pabrik'
                                        : (selectedCodeType.value == 'internal_qr' ? 'QR Code' : 'Code128'),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                )),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // SKU Opsional
                        TextField(
                          controller: skuController,
                          decoration: const InputDecoration(
                            labelText: 'SKU (Opsional)',
                            hintText: 'Kode SKU internal toko',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Harga Jual & Harga Beli (Responsif)
                        Builder(builder: (context) {
                          final sellPriceField = TextField(
                            controller: sellPriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Harga Jual (Rp) *',
                              hintText: 'Misal: 15000',
                              border: OutlineInputBorder(),
                              prefixText: 'Rp ',
                            ),
                          );

                          final costPriceField = TextField(
                            controller: costPriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Harga Beli (Rp)',
                              hintText: 'Misal: 10000',
                              border: OutlineInputBorder(),
                              prefixText: 'Rp ',
                            ),
                          );

                          if (isMobile) {
                            return Column(
                              children: [
                                sellPriceField,
                                if (canViewCost) ...[
                                  const SizedBox(height: 12),
                                  costPriceField,
                                ],
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: sellPriceField),
                              if (canViewCost) ...[
                                const SizedBox(width: 12),
                                Expanded(child: costPriceField),
                              ],
                            ],
                          );
                        }),
                        const SizedBox(height: 14),

                        // ==========================================
                        // MANAJEMEN STOK (TAMBAH / EDIT / TETAP)
                        // ==========================================
                        if (!isEdit) ...[
                          // Tambah Produk Baru: Stok Awal & Stok Minimum
                          Builder(builder: (context) {
                            final initialStockField = TextField(
                              controller: initialStockController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Stok Awal',
                                hintText: '0',
                                border: OutlineInputBorder(),
                              ),
                            );

                            final minStockField = TextField(
                              controller: minStockController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Stok Minimum',
                                hintText: '5',
                                border: OutlineInputBorder(),
                              ),
                            );

                            if (isMobile) {
                              return Column(
                                children: [
                                  initialStockField,
                                  const SizedBox(height: 12),
                                  minStockField,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: initialStockField),
                                const SizedBox(width: 12),
                                Expanded(child: minStockField),
                              ],
                            );
                          }),
                        ] else ...[
                          // Edit Produk: Panel Manajemen Stok Lengkap
                          Container(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Baris Info Stok Saat Ini
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.inventory_2_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 6),
                                        const Text('Manajemen Stok', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (productToEdit.currentStock <= productToEdit.minStock)
                                            ? Colors.orange.shade100
                                            : Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        'Stok Saat Ini: ${productToEdit.currentStock} ${getUnitSymbol(productToEdit.unitId)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11.5,
                                          color: (productToEdit.currentStock <= productToEdit.minStock)
                                              ? Colors.orange.shade900
                                              : Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Pilihan Mode: Tetap / Tambah Stok / Edit/Set Stok
                                Obx(() => Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        ChoiceChip(
                                          label: const Text('Tetap (Tidak Ubah)'),
                                          selected: stockActionMode.value == 'keep',
                                          onSelected: (_) => stockActionMode.value = 'keep',
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        ChoiceChip(
                                          avatar: const Icon(Icons.add_circle_outline, size: 15),
                                          label: const Text('Tambah Stok (+)'),
                                          selected: stockActionMode.value == 'add',
                                          onSelected: (_) => stockActionMode.value = 'add',
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        ChoiceChip(
                                          avatar: const Icon(Icons.edit_outlined, size: 15),
                                          label: const Text('Edit / Set Stok (=)'),
                                          selected: stockActionMode.value == 'set',
                                          onSelected: (_) => stockActionMode.value = 'set',
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    )),
                                const SizedBox(height: 10),

                                // Input Dinamis Sesuai Opsi Mode
                                Obx(() {
                                  final unitSymbol = getUnitSymbol(selectedUnit.value ?? productToEdit.unitId);

                                  if (stockActionMode.value == 'add') {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        TextField(
                                          controller: addStockController,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Jumlah Tambah Stok (+)',
                                            hintText: 'Misal: 10',
                                            border: const OutlineInputBorder(),
                                            suffixText: unitSymbol,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ValueListenableBuilder<TextEditingValue>(
                                          valueListenable: addStockController,
                                          builder: (context, val, _) {
                                            final addQty = int.tryParse(val.text.trim()) ?? 0;
                                            final finalStock = productToEdit.currentStock + addQty;
                                            return Text(
                                              'Stok akan menjadi: ${productToEdit.currentStock} + $addQty = $finalStock $unitSymbol',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: stockNoteController,
                                          decoration: const InputDecoration(
                                            labelText: 'Catatan Mutasi (Opsional)',
                                            hintText: 'Misal: Restock dari supplier',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    );
                                  } else if (stockActionMode.value == 'set') {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        TextField(
                                          controller: setStockController,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Nilai Total Stok Baru (=)',
                                            hintText: 'Misal: 25',
                                            border: const OutlineInputBorder(),
                                            suffixText: unitSymbol,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ValueListenableBuilder<TextEditingValue>(
                                          valueListenable: setStockController,
                                          builder: (context, val, _) {
                                            final newTotal = int.tryParse(val.text.trim()) ?? productToEdit.currentStock;
                                            final diff = newTotal - productToEdit.currentStock;
                                            return Text(
                                              'Stok disesuaikan dari ${productToEdit.currentStock} ke $newTotal (Selisih: ${diff >= 0 ? "+$diff" : diff} $unitSymbol)',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: newTotal < 0 ? Colors.red : Theme.of(context).colorScheme.primary,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: stockNoteController,
                                          decoration: const InputDecoration(
                                            labelText: 'Catatan Mutasi (Opsional)',
                                            hintText: 'Misal: Koreksi fisik / hasil opname',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    );
                                  } else {
                                    return Text(
                                      'Stok saat ini ${productToEdit.currentStock} $unitSymbol tetap dipertahankan.',
                                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    );
                                  }
                                }),
                                const SizedBox(height: 12),

                                // Stok Minimum
                                TextField(
                                  controller: minStockController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Stok Minimum (Peringatan Stok Menipis)',
                                    hintText: '5',
                                    border: const OutlineInputBorder(),
                                    suffixText: getUnitSymbol(selectedUnit.value ?? productToEdit.unitId),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final rawName = nameController.text.trim();
                        final sellPrice = int.tryParse(sellPriceController.text.trim()) ?? -1;
                        final costPrice = int.tryParse(costPriceController.text.trim()) ?? 0;
                        final initialStock = int.tryParse(initialStockController.text.trim()) ?? 0;
                        final minStock = int.tryParse(minStockController.text.trim()) ?? 0;
                        final barcode = barcodeController.text.trim().isEmpty ? null : barcodeController.text.trim();
                        final internalCode = internalCodeController.text.trim().isEmpty
                            ? null
                            : internalCodeController.text.trim();
                        final sku = skuController.text.trim().isEmpty ? null : skuController.text.trim();

                        if (rawName.isEmpty) {
                          Get.snackbar('Validasi Gagal', 'Nama produk wajib diisi');
                          return;
                        }
                        if (sellPrice < 0) {
                          Get.snackbar('Validasi Gagal', 'Harga jual harus berupa angka valid >= 0');
                          return;
                        }

                        // Validasi stok jika mode edit
                        int computedStockDelta = 0;
                        if (isEdit) {
                          if (stockActionMode.value == 'add') {
                            final addQty = int.tryParse(addStockController.text.trim()) ?? 0;
                            if (addQty < 0) {
                              Get.snackbar('Validasi Gagal', 'Jumlah tambah stok tidak boleh negatif');
                              return;
                            }
                            computedStockDelta = addQty;
                          } else if (stockActionMode.value == 'set') {
                            final targetStock = int.tryParse(setStockController.text.trim());
                            if (targetStock == null || targetStock < 0) {
                              Get.snackbar('Validasi Gagal', 'Nilai stok baru harus berupa angka >= 0');
                              return;
                            }
                            computedStockDelta = targetStock - productToEdit.currentStock;
                          }
                        }

                        // Cek apakah barcode sudah ada di produk lain
                        if (barcode != null) {
                          final existing = await _productRepo.getProductByBarcode(barcode);
                          if (existing != null && (!isEdit || existing.id != productToEdit.id)) {
                            if (!context.mounted) return;
                            final openExisting = await ConfirmDialog.show(
                              context: context,
                              title: 'Barcode Sudah Ada',
                              message:
                                  'Barcode "$barcode" sudah terdaftar pada produk "${existing.name}".\n\nApakah Anda ingin membuka produk tersebut untuk diedit?',
                              confirmText: 'Buka Produk',
                              cancelText: 'Batal',
                            );
                            if (openExisting) {
                              Get.back(); // Tutup dialog saat ini
                              if (context.mounted) {
                                showProductFormDialog(context: context, productToEdit: existing);
                              }
                            }
                            return;
                          }
                        }

                        try {
                          if (isEdit) {
                            await updateProductData(
                              oldProduct: productToEdit,
                              name: rawName,
                              sellPrice: sellPrice,
                              costPrice: costPrice,
                              minStock: minStock,
                              categoryId: selectedCat.value,
                              unitId: selectedUnit.value,
                              sku: sku,
                              barcode: barcode,
                              internalCode: internalCode,
                              codeType: selectedCodeType.value,
                              stockActionMode: stockActionMode.value,
                              stockDelta: computedStockDelta,
                              stockNote: stockNoteController.text.trim(),
                            );
                            Get.back();
                            Get.snackbar(
                              'Sukses',
                              'Produk "$rawName" berhasil diperbarui',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          } else {
                            await addProduct(
                              name: rawName,
                              sellPrice: sellPrice,
                              costPrice: costPrice,
                              initialStock: initialStock,
                              minStock: minStock,
                              categoryId: selectedCat.value,
                              unitId: selectedUnit.value,
                              sku: sku,
                              barcode: barcode,
                              internalCode: internalCode,
                              codeType: selectedCodeType.value,
                            );
                            Get.back();
                            Get.snackbar(
                              'Sukses',
                              'Produk "$rawName" berhasil ditambahkan',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          }
                        } on LimitReachedException {
                          // Handled in addProduct
                        } on AppException catch (e) {
                          e.showSnackbar();
                        } catch (e) {
                          Get.snackbar('Error', 'Gagal menyimpan produk: $e');
                        }
                      },
                      child: Text(isEdit ? 'Simpan Perubahan' : 'Simpan Produk'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (Get.isRegistered<ScannerService>()) {
        ScannerService.to.unregisterConsumer('product_form');
      }
    });
  }

  /// Dialog Cepat Penyesuaian / Tambah Stok Langsung dari Kartu Produk
  void showStockAdjustmentDialog({
    required BuildContext context,
    required Product product,
  }) {
    if (!canEdit) {
      Get.snackbar('Akses Ditolak', 'Anda tidak memiliki hak akses mengubah stok.');
      return;
    }

    if (isProductLocked(product)) {
      Get.snackbar(
        'Produk Terkunci',
        'Produk ini terkunci oleh kuota tier lisensi.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final RxString mode = 'add'.obs; // 'add' | 'set'
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();
    final unitSymbol = getUnitSymbol(product.unitId);
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    Get.dialog(
      Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 32,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kelola Stok Produk',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              product.name,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Get.back(),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Info Stok Saat Ini
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stok Saat Ini:', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          '${product.currentStock} $unitSymbol',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pilihan Mode: Tambah (+) / Set/Koreksi (=)
                  Obx(() => Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              avatar: const Icon(Icons.add_circle_outline, size: 16),
                              label: const Center(child: Text('Tambah (+)')),
                              selected: mode.value == 'add',
                              onSelected: (_) => mode.value = 'add',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              avatar: const Icon(Icons.edit_outlined, size: 16),
                              label: const Center(child: Text('Set / Edit (=)')),
                              selected: mode.value == 'set',
                              onSelected: (_) {
                                mode.value = 'set';
                                qtyController.text = product.currentStock.toString();
                              },
                            ),
                          ),
                        ],
                      )),
                  const SizedBox(height: 16),

                  // Input Jumlah
                  Obx(() => TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: mode.value == 'add' ? 'Jumlah Tambahan Stok (+)' : 'Total Stok Baru (=)',
                          hintText: mode.value == 'add' ? 'Contoh: 10' : 'Contoh: 25',
                          border: const OutlineInputBorder(),
                          suffixText: unitSymbol,
                        ),
                      )),
                  const SizedBox(height: 8),

                  // Perhitungan Live Preview
                  Obx(() {
                    return ValueListenableBuilder<TextEditingValue>(
                      valueListenable: qtyController,
                      builder: (context, val, _) {
                        final inputVal = int.tryParse(val.text.trim()) ?? 0;
                        int finalStock = 0;
                        String desc = '';
                        if (mode.value == 'add') {
                          finalStock = product.currentStock + inputVal;
                          desc = 'Stok akhir: ${product.currentStock} + $inputVal = $finalStock $unitSymbol';
                        } else {
                          finalStock = inputVal;
                          final diff = finalStock - product.currentStock;
                          desc = 'Stok akhir: $finalStock $unitSymbol (Selisih: ${diff >= 0 ? "+$diff" : diff})';
                        }

                        return Text(
                          desc,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: finalStock < 0 ? Colors.red : Theme.of(context).colorScheme.primary,
                          ),
                        );
                      },
                    );
                  }),
                  const SizedBox(height: 12),

                  // Catatan Mutasi
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan Mutasi (Opsional)',
                      hintText: 'Misal: Masuk dari Supplier / Hasil Opname',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tombol Aksi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('Batal'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final val = int.tryParse(qtyController.text.trim());
                          if (val == null) {
                            Get.snackbar('Validasi Gagal', 'Masukkan jumlah angka yang valid');
                            return;
                          }
                          if (mode.value == 'add' && val <= 0) {
                            Get.snackbar('Validasi Gagal', 'Jumlah penambahan stok harus lebih dari 0');
                            return;
                          }
                          if (mode.value == 'set' && val < 0) {
                            Get.snackbar('Validasi Gagal', 'Stok baru tidak boleh negatif');
                            return;
                          }

                          try {
                            await adjustStock(
                              product: product,
                              mode: mode.value,
                              qty: val,
                              note: noteController.text.trim(),
                            );
                            Get.back();
                            Get.snackbar(
                              'Stok Diperbarui',
                              'Stok "${product.name}" berhasil diperbarui',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          } on AppException catch (e) {
                            e.showSnackbar();
                          } catch (e) {
                            Get.snackbar('Error', 'Gagal memperbarui stok: $e');
                          }
                        },
                        child: const Text('Simpan Stok'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
