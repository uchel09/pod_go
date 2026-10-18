import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/pdf/label_pdf_service.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/product_repository.dart';

class ProductLabelsController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final allProducts = <Product>[].obs;
  final selectedProductIds = <int>{}.obs;
  final productCopies = <int, int>{}.obs; // productId -> copies count

  final selectedTemplate = LabelTemplateType.roll3Col40x20.obs;
  final selectedFormat = LabelBarcodeFormat.code128.obs;
  final showPrice = true.obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  bool get canView => PermissionService.to.can(PermissionKeys.productView);

  @override
  void onInit() {
    super.onInit();
    _initScannerTypeDefault();
    _loadProducts();
  }

  void _initScannerTypeDefault() {
    final scannerType = AuthService.to.currentStore.value?.scannerType;
    if (scannerType == '2d') {
      selectedFormat.value = LabelBarcodeFormat.qr;
    } else {
      selectedFormat.value = LabelBarcodeFormat.code128;
    }
  }

  Future<void> _loadProducts() async {
    isLoading.value = true;
    try {
      final list = await _productRepo.getAllProducts();
      // Hanya ambil produk aktif yang memiliki barcode atau kode internal
      final validList = list.where((p) => p.isActive && (p.barcode != null || p.internalCode != null)).toList();
      allProducts.value = validList;

      // Cek apakah ada argumen productId dari halaman sebelumnya (misal dari detail produk)
      final targetProductId = Get.arguments is Map ? Get.arguments['productId'] as int? : null;

      if (targetProductId != null) {
        selectedProductIds.assignAll({targetProductId});
        productCopies[targetProductId] = 1;
      } else {
        // Default: Hanya pilih produk tanpa barcode pabrik (codeType != 'manufacturer')
        // Produk kemasan pabrik TIDAK masuk daftar default
        final internalOnly = validList
            .where((p) => p.codeType != 'manufacturer')
            .map((p) => p.id)
            .toSet();
        selectedProductIds.assignAll(internalOnly);
        for (final p in validList) {
          productCopies[p.id] = 1;
        }
      }
    } finally {
      isLoading.value = false;
    }
  }

  List<Product> get filteredProducts {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return allProducts;
    return allProducts.where((p) {
      final nameMatch = p.name.toLowerCase().contains(query);
      final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
      final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
      final codeMatch = p.internalCode?.toLowerCase().contains(query) ?? false;
      return nameMatch || skuMatch || barcodeMatch || codeMatch;
    }).toList();
  }

  /// Daftar item terpilih beserta jumlah cetakannya untuk PDF
  List<LabelPrintItem> get selectedItemsToPrint {
    final list = <LabelPrintItem>[];
    for (final p in allProducts) {
      if (selectedProductIds.contains(p.id)) {
        final copies = productCopies[p.id] ?? 1;
        if (copies > 0) {
          list.add(LabelPrintItem(product: p, copies: copies));
        }
      }
    }
    return list;
  }

  int get totalLabelsCount {
    int total = 0;
    for (final id in selectedProductIds) {
      total += productCopies[id] ?? 1;
    }
    return total;
  }

  List<String> get currentWarnings {
    return LabelPdfService.checkWarnings(
      items: selectedItemsToPrint,
      template: selectedTemplate.value,
      format: selectedFormat.value,
    );
  }

  void toggleProductSelection(int productId) {
    if (selectedProductIds.contains(productId)) {
      selectedProductIds.remove(productId);
    } else {
      selectedProductIds.add(productId);
      productCopies.putIfAbsent(productId, () => 1);
    }
  }

  void selectAllInternalProducts() {
    final internalIds = allProducts
        .where((p) => p.codeType != 'manufacturer')
        .map((p) => p.id)
        .toSet();
    selectedProductIds.assignAll(internalIds);
  }

  void selectAllFiltered() {
    selectedProductIds.addAll(filteredProducts.map((p) => p.id));
  }

  void deselectAll() {
    selectedProductIds.clear();
  }

  void updateCopies(int productId, int copies) {
    if (copies <= 0) return;
    productCopies[productId] = copies;
  }

  void setBulkCopies(int copies) {
    if (copies <= 0) return;
    for (final id in selectedProductIds) {
      productCopies[id] = copies;
    }
  }

  Future<Uint8List> generatePdfBytes() async {
    return LabelPdfService.generatePdf(
      items: selectedItemsToPrint,
      template: selectedTemplate.value,
      format: selectedFormat.value,
      showPrice: showPrice.value,
    );
  }

  Future<void> printPdf() async {
    if (selectedItemsToPrint.isEmpty) {
      Get.snackbar(
        'Peringatan',
        'Pilih minimal satu produk untuk dicetak.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      await Printing.layoutPdf(
        onLayout: (format) => generatePdfBytes(),
        name: 'label_produk_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      Get.snackbar('Error Cetak', 'Gagal membuka dialog cetak: $e');
    }
  }

  Future<void> sharePdf() async {
    if (selectedItemsToPrint.isEmpty) {
      Get.snackbar(
        'Peringatan',
        'Pilih minimal satu produk untuk disimpan/dibagikan.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      final bytes = await generatePdfBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'label_produk_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      Get.snackbar('Error Simpan PDF', 'Gagal membagikan/menyimpan PDF: $e');
    }
  }
}
