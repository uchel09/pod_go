import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/printing/printer_manager.dart';
import '../../../core/printing/receipt_actions.dart';
import '../../../core/printing/receipt_data_mapper.dart';
import '../../../core/printing/receipt_mode.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/services/scanner/scanner_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../routes/app_pages.dart';
import '../../sale_success/sale_success_args.dart';

class PosCartItem {
  final Product product;
  final RxInt qty;
  final RxInt discount; // Rupiah per unit

  PosCartItem({
    required this.product,
    int initialQty = 1,
    int initialDiscount = 0,
  })  : qty = initialQty.obs,
        discount = initialDiscount.obs;

  int get subtotal => (product.sellPrice - discount.value) * qty.value;
}

class HeldCart {
  final String id;
  final String name;
  final List<PosCartItem> items;
  final int overallDiscount;
  final bool isOverallDiscountPercent;
  final DateTime heldAt;

  HeldCart({
    required this.id,
    required this.name,
    required this.items,
    required this.overallDiscount,
    required this.isOverallDiscountPercent,
    required this.heldAt,
  });
}

class PosController extends GetxController {
  static PosController get to => Get.find<PosController>();

  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final CategoryRepository _categoryRepo = Get.find<CategoryRepository>();
  final SaleRepository _saleRepo = Get.find<SaleRepository>();
  final SettingsRepository _settingsRepo = Get.find<SettingsRepository>();

  final allProducts = <Product>[].obs;
  final categories = <Category>[].obs;

  final cartItems = <PosCartItem>[].obs;
  final heldCarts = <HeldCart>[].obs;

  final selectedCategoryId = Rxn<int>();
  final searchQuery = ''.obs;
  final searchController = TextEditingController();

  final favoriteProductIds = <int>{}.obs;
  final onlyFavoritesFilter = false.obs;

  final allowNegativeStock = false.obs;
  final receiptWidth = '58'.obs; // '58' | '80'

  final overallDiscountValue = 0.obs;
  final isOverallDiscountPercent = false.obs;

  final lastCheckoutResult = Rxn<CheckoutResult>();
  final isLoading = true.obs;

  /// True selama transaksi sedang disimpan. Tombol Bayar dinonaktifkan dan
  /// [processCheckout] menolak panggilan kedua (anti transaksi ganda).
  final isSaving = false.obs;

  /// Fokus kolom cari/scan; dipakai tombol "Transaksi Baru".
  final searchFocusNode = FocusNode();

  // Permissions & Limits
  bool get canSell => PermissionService.to.can(PermissionKeys.posSell);
  bool get canDiscount => PermissionService.to.can(PermissionKeys.posDiscount);
  bool get canVoid => PermissionService.to.can(PermissionKeys.posVoid);
  bool get canViewHistory => canSell || canVoid;
  bool get canEditProduct => PermissionService.to.can(PermissionKeys.productEdit);
  bool get isCameraSupported => ScannerService.to.isCameraSupported;

  int? get tierLimit => FeatureGate.to.productLimit;

  /// Kumpulan ID produk yang terkunci (read-only) karena tier lisensi turun
  Set<int> get lockedProductIds {
    final limit = tierLimit;
    if (limit == null) return {};

    final activeSorted = allProducts.where((p) => p.isActive).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (activeSorted.length <= limit) return {};
    return activeSorted.skip(limit).map((p) => p.id).toSet();
  }

  bool isProductLocked(Product product) => lockedProductIds.contains(product.id);

  @override
  void onInit() {
    super.onInit();
    _bindStreams();
    _loadSettings();
    _registerScannerConsumer();
  }

  @override
  void onClose() {
    ScannerService.to.unregisterConsumer('pos');
    searchController.dispose();
    searchFocusNode.dispose();
    super.onClose();
  }

  void _bindStreams() {
    allProducts.bindStream(
      _productRepo.watchAllProducts().map((list) {
        isLoading.value = false;
        return list.where((p) => p.isActive).toList();
      }),
    );
    categories.bindStream(_categoryRepo.watchAllCategories());
  }

  Future<void> _loadSettings() async {
    // 1. Izinkan Stok Minus
    final negStockVal = await _settingsRepo.getSetting('pos.allow_negative_stock');
    allowNegativeStock.value = negStockVal == 'true';

    // 2. Lebar Struk
    final rWidth = await _settingsRepo.getSetting('pos.receipt_width');
    if (rWidth != null && (rWidth == '58' || rWidth == '80')) {
      receiptWidth.value = rWidth;
    }

    // 3. Produk Favorit
    final favStr = await _settingsRepo.getSetting('pos.favorite_product_ids');
    if (favStr != null && favStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(favStr) as List;
        favoriteProductIds.assignAll(decoded.map((e) => e as int).toSet());
      } catch (_) {}
    }
  }

  void _registerScannerConsumer() {
    ScannerService.to.registerConsumer('pos', (scannedCode) {
      onBarcodeScanned(scannedCode);
    });
  }

  void _notify(
    String title,
    String message, {
    SnackPosition snackPosition = SnackPosition.TOP,
    Duration? duration,
    TextButton? mainButton,
  }) {
    if (Get.context != null) {
      Get.snackbar(
        title,
        message,
        snackPosition: snackPosition,
        duration: duration ?? const Duration(seconds: 3),
        mainButton: mainButton,
      );
    }
  }

  /// Menangani barcode dari hardware HID USB/Bluetooth atau Kamera
  void onBarcodeScanned(String code) {
    if (!canSell) {
      _notify('Akses Ditolak', 'Anda tidak memiliki izin kasir (pos.sell).');
      return;
    }

    final query = code.trim().toLowerCase();
    final match = allProducts.firstWhereOrNull((p) {
      final barcodeMatch = p.barcode?.toLowerCase() == query;
      final internalMatch = p.internalCode?.toLowerCase() == query;
      final skuMatch = p.sku?.toLowerCase() == query;
      return barcodeMatch || internalMatch || skuMatch;
    });

    if (match != null) {
      if (isProductLocked(match)) {
        _notify(
          'Produk Terkunci',
          'Produk "${match.name}" terkunci oleh batas tier dan tidak dapat dijual.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      addToCart(match);
      _notify(
        'Ditambahkan ke Keranjang',
        '${match.name} (Qty: ${_getCartItemQty(match.id)})',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
    } else {
      _notify(
        'Produk Tidak Terdaftar',
        'Kode barcode "$code" belum terdaftar di toko.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
        mainButton: canEditProduct
            ? TextButton(
                onPressed: () => Get.toNamed(Routes.PRODUCTS),
                child: const Text('DAFTARKAN', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
              )
            : null,
      );
    }
  }

  int _getCartItemQty(int productId) {
    final item = cartItems.firstWhereOrNull((i) => i.product.id == productId);
    return item?.qty.value ?? 0;
  }

  /// Filter produk untuk Grid/List tampilan kasir
  List<Product> get filteredProducts {
    var list = allProducts.toList();

    // Prioritaskan produk favorit di urutan atas
    list.sort((a, b) {
      final aFav = favoriteProductIds.contains(a.id);
      final bFav = favoriteProductIds.contains(b.id);
      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      return a.name.compareTo(b.name);
    });

    // Filter Favorit Saja
    if (onlyFavoritesFilter.value) {
      list = list.where((p) => favoriteProductIds.contains(p.id)).toList();
    }

    // Filter Kategori
    if (selectedCategoryId.value != null) {
      list = list.where((p) => p.categoryId == selectedCategoryId.value).toList();
    }

    // Filter Pencarian (nama, barcode, sku, internalCode)
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

    return list;
  }

  void updateSearch(String val) {
    searchQuery.value = val;
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }

  void filterByCategory(int? catId) {
    selectedCategoryId.value = catId;
  }

  Future<void> toggleFavorite(int productId) async {
    if (favoriteProductIds.contains(productId)) {
      favoriteProductIds.remove(productId);
    } else {
      favoriteProductIds.add(productId);
    }
    await _settingsRepo.setSetting(
      'pos.favorite_product_ids',
      jsonEncode(favoriteProductIds.toList()),
    );
  }

  Future<void> setAllowNegativeStock(bool allow) async {
    allowNegativeStock.value = allow;
    await _settingsRepo.setSetting('pos.allow_negative_stock', allow ? 'true' : 'false');
  }

  Future<void> setReceiptWidth(String width) async {
    receiptWidth.value = width;
    await _settingsRepo.setSetting('pos.receipt_width', width);
  }

  // --- Operasi Keranjang Belanja ---

  void addToCart(Product product) {
    if (!canSell) {
      _notify('Akses Ditolak', 'Anda tidak memiliki hak akses kasir.');
      return;
    }

    if (isProductLocked(product)) {
      _notify(
        'Produk Terkunci',
        'Produk "${product.name}" terkunci oleh batas tier lisensi.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final existing = cartItems.firstWhereOrNull((i) => i.product.id == product.id);
    if (existing != null) {
      updateQty(existing, existing.qty.value + 1);
    } else {
      // Cek stok awal jika stok minus dilarang
      if (!allowNegativeStock.value && product.currentStock <= 0) {
        _notify(
          'Stok Habis',
          'Stok produk "${product.name}" kosong (${product.currentStock}). '
          'Aktifkan "Izinkan Stok Minus" di Pengaturan POS jika ingin melanjutkan.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      cartItems.add(PosCartItem(product: product, initialQty: 1));
    }
  }

  void updateQty(PosCartItem item, int newQty) {
    if (newQty <= 0) {
      removeFromCart(item);
      return;
    }

    if (!allowNegativeStock.value && newQty > item.product.currentStock) {
      _notify(
        'Peringatan Stok',
        'Stok "${item.product.name}" hanya tersedia ${item.product.currentStock}.',
        snackPosition: SnackPosition.BOTTOM,
      );
      item.qty.value = item.product.currentStock > 0 ? item.product.currentStock : 1;
      return;
    }

    item.qty.value = newQty;
  }

  void removeFromCart(PosCartItem item) {
    cartItems.remove(item);
  }

  void clearCart() {
    cartItems.clear();
    overallDiscountValue.value = 0;
    isOverallDiscountPercent.value = false;
  }

  void setItemDiscount(PosCartItem item, int discountRupiah) {
    if (!canDiscount) {
      _notify('Akses Ditolak', 'Anda tidak memiliki izin memberikan diskon.');
      return;
    }
    item.discount.value = discountRupiah.clamp(0, item.product.sellPrice);
  }

  void setOverallDiscount(int val, {bool isPercent = false}) {
    if (!canDiscount) {
      _notify('Akses Ditolak', 'Anda tidak memiliki izin memberikan diskon.');
      return;
    }
    isOverallDiscountPercent.value = isPercent;
    overallDiscountValue.value = val;
  }

  // --- Perhitungan Angka Keranjang ---

  int get subtotalAmount {
    return cartItems.fold<int>(0, (sum, i) => sum + (i.product.sellPrice * i.qty.value));
  }

  int get itemsDiscountTotal {
    return cartItems.fold<int>(0, (sum, i) => sum + (i.discount.value * i.qty.value));
  }

  int get calculatedOverallDiscount {
    final base = subtotalAmount - itemsDiscountTotal;
    if (base <= 0) return 0;
    if (isOverallDiscountPercent.value) {
      final percent = overallDiscountValue.value.clamp(0, 100);
      return (base * percent / 100).round();
    }
    return overallDiscountValue.value.clamp(0, base);
  }

  int get totalDiscountAmount => itemsDiscountTotal + calculatedOverallDiscount;

  int get finalTotalAmount {
    final res = subtotalAmount - totalDiscountAmount;
    return res > 0 ? res : 0;
  }

  int get totalItemsQty => cartItems.fold<int>(0, (sum, i) => sum + i.qty.value);

  // --- Fitur Hold / Resume Keranjang ---

  void holdCurrentCart({String? customName}) {
    if (cartItems.isEmpty) {
      _notify('Keranjang Kosong', 'Tidak ada barang untuk ditahan.');
      return;
    }

    final id = const Uuid().v4();
    final name = customName ?? 'Keranjang #${heldCarts.length + 1}';

    // Salin item agar tidak terpengaruh saat keranjang aktif di-clear
    final copiedItems = cartItems.map((item) {
      return PosCartItem(
        product: item.product,
        initialQty: item.qty.value,
        initialDiscount: item.discount.value,
      );
    }).toList();

    heldCarts.add(
      HeldCart(
        id: id,
        name: name,
        items: copiedItems,
        overallDiscount: overallDiscountValue.value,
        isOverallDiscountPercent: isOverallDiscountPercent.value,
        heldAt: DateTime.now(),
      ),
    );

    clearCart();
    _notify(
      'Keranjang Ditahan',
      'Pesanan "$name" berhasil ditahan.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void resumeHeldCart(HeldCart held) {
    if (cartItems.isNotEmpty) {
      // Tahan keranjang aktif terlebih dahulu otomatis
      holdCurrentCart(customName: 'Ditahan Sebelum Melanjutkan');
    }

    cartItems.assignAll(held.items);
    overallDiscountValue.value = held.overallDiscount;
    isOverallDiscountPercent.value = held.isOverallDiscountPercent;
    heldCarts.remove(held);

    _notify(
      'Keranjang Dipulihkan',
      'Pesanan "${held.name}" siap diproses.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void deleteHeldCart(HeldCart held) {
    heldCarts.remove(held);
  }

  // --- Pembayaran & Simpan Transaksi ---

  /// Mode struk aktif (ask/always/never). Default [ReceiptMode.ask] bila layanan
  /// printer belum terdaftar.
  ReceiptMode get receiptMode => _printerManager?.receiptMode.value ?? ReceiptMode.ask;

  PrinterManager? get _printerManager =>
      Get.isRegistered<PrinterManager>() ? PrinterManager.to : null;

  /// Menyimpan transaksi lalu mengosongkan keranjang.
  ///
  /// Struk BUKAN bagian dari jalur ini. Setelah transaksi tersimpan, alur struk
  /// ([_runReceiptFlow]) berjalan terpisah dan hasilnya (berhasil/gagal) tidak pernah
  /// mengubah transaksi. Mengembalikan null bila panggilan diabaikan karena transaksi
  /// lain sedang disimpan (guard [isSaving] mencegah transaksi ganda saat tombol
  /// Bayar diketuk dua kali).
  Future<CheckoutResult?> processCheckout({
    required List<CheckoutPayment> payments,
  }) async {
    if (isSaving.value) return null;

    if (!canSell) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin kasir (pos.sell).');
    }
    if (cartItems.isEmpty) {
      throw const AppException('Keranjang belanja kosong.');
    }

    final user = AuthService.to.currentUser.value;
    if (user == null) {
      throw const AppException('Sesi kasir tidak valid. Silakan login kembali.');
    }

    final deviceId = DeviceIdService.to.deviceId;

    final checkoutItems = cartItems.map((i) {
      return CheckoutCartItem(
        productId: i.product.id,
        productName: i.product.name,
        qty: i.qty.value,
        price: i.product.sellPrice,
        costPrice: i.product.costPrice,
        discount: i.discount.value,
      );
    }).toList();

    // Dikunci secara sinkron sebelum await pertama, sehingga panggilan kedua yang
    // datang sebelum penyimpanan selesai langsung ditolak di guard di atas.
    isSaving.value = true;
    try {
      // 1. Transaksi atomik di SQLite via Drift (sales, items, payments, stok)
      final result = await _saleRepo.checkout(
        cashierId: user.id,
        deviceId: deviceId,
        items: checkoutItems,
        payments: payments,
        overallDiscount: calculatedOverallDiscount,
        allowNegativeStock: allowNegativeStock.value,
      );

      // 2. Transaksi sudah aman di database: kosongkan keranjang
      clearCart();
      lastCheckoutResult.value = result;

      // 3. Audit diskon besar + alur struk terpisah (tidak pernah melempar exception)
      _checkDiscountAudit(result.sale, user.displayName);
      receiptFlowDone = _runReceiptFlow(result, cashierName: user.displayName);

      return result;
    } finally {
      isSaving.value = false;
    }
  }

  /// Selesai ketika alur struk pasca-checkout (laci kasir, cetak otomatis) selesai.
  /// Hanya untuk pengujian; transaksi sudah tersimpan jauh sebelum ini selesai.
  Future<void> receiptFlowDone = Future<void>.value();

  /// Argumen layar sukses terakhir yang diminta alur struk (null bila tidak membuka layar).
  SaleSuccessArgs? lastSuccessArgs;

  /// Alur struk setelah transaksi tersimpan, sesuai [ReceiptMode]:
  /// - ask: buka layar sukses dengan pilihan cetak/PDF/selesai
  /// - always: cetak otomatis (bila ada printer hardware) lalu layar sukses singkat
  /// - never: kembali ke transaksi baru, snackbar "Transaksi tersimpan" + tombol Cetak
  ///
  /// Seluruh kegagalan di sini ditelan: transaksi tidak boleh terpengaruh.
  Future<void> _runReceiptFlow(CheckoutResult result, {required String cashierName}) async {
    try {
      final manager = _printerManager;

      // Laci kasir adalah peristiwa pembayaran tunai, bukan bagian dari cetak,
      // sehingga tetap terbuka pada semua mode (termasuk tanpa struk).
      if (manager != null &&
          manager.cashDrawer.value &&
          hasCashPayment(result.payments.map((p) => p.method))) {
        unawaited(manager.openCashDrawer());
      }

      final receipt = buildReceiptData(
        store: AuthService.to.currentStore.value,
        cashierName: cashierName,
        sale: result.sale,
        items: result.items,
        payments: result.payments,
      );

      switch (receiptMode) {
        case ReceiptMode.ask:
          _openSuccessScreen(SaleSuccessArgs(saleId: result.sale.id));
        case ReceiptMode.always:
          if (manager != null && manager.shouldAutoPrint) {
            final job = ReceiptActions.print(receipt);
            _openSuccessScreen(SaleSuccessArgs(saleId: result.sale.id, autoPrintJob: job));
            await job;
          } else {
            // Tanpa printer hardware tidak ada yang bisa dicetak otomatis.
            _openSuccessScreen(SaleSuccessArgs(saleId: result.sale.id));
          }
        case ReceiptMode.never:
          lastSuccessArgs = null;
          ReceiptActions.showSavedWithPrintOption(receipt);
          focusSearch();
      }
    } catch (e) {
      debugPrint('Alur struk gagal (transaksi tetap tersimpan): $e');
    }
  }

  void _openSuccessScreen(SaleSuccessArgs args) {
    lastSuccessArgs = args;
    // Tanpa navigator (mis. unit test) cukup catat; transaksi tidak terpengaruh.
    if (Get.key.currentState == null) return;
    Get.toNamed(Routes.SALE_SUCCESS, arguments: args);
  }

  /// Mengembalikan fokus ke kolom cari/scan untuk transaksi berikutnya.
  void focusSearch() {
    searchFocusNode.requestFocus();
    // Di Android scanner HID tetap mengetik ke kolom ini; keyboard layar tidak perlu muncul.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  }

  void _checkDiscountAudit(Sale sale, String cashierName) async {
    final threshNominalStr = await _settingsRepo.getSetting('pos.discount_audit_threshold_nominal');
    final threshPercentStr = await _settingsRepo.getSetting('pos.discount_audit_threshold_percent');

    final threshNominal = int.tryParse(threshNominalStr ?? '') ?? 50000;
    final threshPercent = int.tryParse(threshPercentStr ?? '') ?? 20;

    final discountTotal = sale.discount;
    final percent = sale.subtotal > 0 ? (discountTotal * 100 / sale.subtotal).round() : 0;

    if (discountTotal >= threshNominal || percent >= threshPercent) {
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'pos.high_discount',
          entity: 'sales',
          entityId: sale.id,
          detail: {
            'invoice': sale.invoiceNo,
            'discount': discountTotal,
            'percent': percent,
            'thresholdNominal': threshNominal,
            'thresholdPercent': threshPercent,
            'cashier': cashierName,
          },
        );
      }
    }
  }

  /// Membuka laci kasir manual (tombol di toolbar kasir).
  Future<void> openCashDrawer() async {
    await _printerManager?.openCashDrawer();
  }

  void scanWithCamera() async {
    final code = await ScannerService.to.scanWithCamera();
    if (code != null) {
      onBarcodeScanned(code);
    }
  }
}
