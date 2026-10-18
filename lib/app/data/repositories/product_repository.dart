import 'package:get/get.dart' hide Value;

import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/settings_dao.dart';
import '../local/daos/store_dao.dart';

class ProductRepository {
  final ProductDao _dao;
  final SettingsDao? _settingsDao;
  final StoreDao? _storeDao;
  final FeatureGate? _featureGate;

  ProductRepository(
    this._dao, {
    SettingsDao? settingsDao,
    StoreDao? storeDao,
    FeatureGate? featureGate,
  })  : _settingsDao = settingsDao,
        _storeDao = storeDao,
        _featureGate = featureGate;

  FeatureGate? get _activeFeatureGate {
    if (_featureGate != null) return _featureGate;
    if (Get.isRegistered<FeatureGate>()) {
      return FeatureGate.to;
    }
    return null;
  }

  Future<List<Product>> getAllProducts() => _dao.getAllProducts();
  Stream<List<Product>> watchAllProducts() => _dao.watchAllProducts();
  Future<Product?> getProductById(int id) => _dao.getProductById(id);
  Future<Product?> getProductByBarcode(String barcode) => _dao.getProductByBarcode(barcode);
  Future<Product?> getProductByInternalCode(String code) => _dao.getProductByInternalCode(code);
  Future<Product?> getProductBySku(String sku) => _dao.getProductBySku(sku);
  Future<Product?> getProductByBarcodeOrInternalCode(String code) =>
      _dao.getProductByBarcodeOrInternalCode(code);

  Future<List<Product>> getActiveProductsOrderedByCreatedAt() =>
      _dao.getActiveProductsOrderedByCreatedAt();
  Stream<List<Product>> watchActiveProductsOrderedByCreatedAt() =>
      _dao.watchActiveProductsOrderedByCreatedAt();

  Future<int> countActiveProducts() => _dao.countActiveProducts();
  Stream<int> watchActiveProductsCount() => _dao.watchActiveProductsCount();

  Future<int> countProductsByCategoryId(int categoryId) =>
      _dao.countProductsByCategoryId(categoryId);
  Future<int> countProductsByUnitId(int unitId) =>
      _dao.countProductsByUnitId(unitId);

  Future<int> updateProductStock(int id, int newStock) =>
      _dao.updateProductStock(id, newStock);
  Future<int> setProductActive(int id, bool isActive) =>
      _dao.setProductActive(id, isActive);

  Future<bool> updateProduct(ProductsCompanion product) =>
      _dao.updateProduct(product);
  Future<int> deleteProduct(int id) => _dao.deleteProduct(id);

  /// Alias insertProduct yang memanggil createProduct (termasuk pengecekan tier limit)
  Future<int> insertProduct(ProductsCompanion product) => createProduct(product);

  /// Menambah produk baru dengan pengecekan batas produk aktif tier lisensi
  Future<int> createProduct(ProductsCompanion product) async {
    final limit = _activeFeatureGate?.productLimit;
    if (limit != null) {
      final activeCount = await _dao.countActiveProducts();
      if (activeCount >= limit) {
        throw LimitReachedException(
          'Batas maksimal $limit produk aktif telah tercapai pada tier Gratis.\n\nSilakan upgrade ke tier Semi-Premium untuk menikmati produk tanpa batas.',
          limit: limit,
        );
      }
    }

    return _dao.insertProduct(product);
  }

  /// Membuat kode internal unik dengan format P + 6 digit (contoh: P000001)
  /// Kode dipastikan tidak pernah duplikat dengan produk yang sudah ada.
  Future<Map<String, String>> generateInternalCode() async {
    // 1. Tentukan jenis kode berdasarkan scanner type toko (1d = internal_code128, 2d = internal_qr)
    String codeType = 'internal_code128';
    if (_storeDao != null) {
      final store = await _storeDao.getStore();
      if (store?.scannerType.toLowerCase() == '2d') {
        codeType = 'internal_qr';
      }
    }

    // 2. Ambil counter dari settings / cari kode yang belum dipakai
    const settingKey = 'internal_product_counter';
    int counter = 1;

    while (true) {
      if (_settingsDao != null) {
        counter = await _settingsDao.getNextCounter(settingKey, defaultValue: counter);
      }

      final candidateCode = 'P${counter.toString().padLeft(6, '0')}';

      // Pastikan kandidat kode belum ada di tabel produk (baik barcode maupun internalCode)
      final existing = await _dao.getProductByBarcodeOrInternalCode(candidateCode);
      if (existing == null) {
        return {
          'code': candidateCode,
          'codeType': codeType,
        };
      }

      counter++;
    }
  }

  /// Menentukan kumpulan ID produk yang terkunci (read-only) karena tier lisensi turun
  /// Produk aktif di luar urutan batas tier (berdasarkan createdAt terawal) akan terkunci.
  Future<Set<int>> getLockedProductIds() async {
    final limit = _activeFeatureGate?.productLimit;
    if (limit == null) return {};

    final activeList = await _dao.getActiveProductsOrderedByCreatedAt();
    if (activeList.length <= limit) return {};

    return activeList.skip(limit).map((p) => p.id).toSet();
  }

  /// Memeriksa apakah produk tertentu sedang terkunci oleh batas tier
  Future<bool> isProductLockedByTier(Product product) async {
    final limit = _activeFeatureGate?.productLimit;
    if (limit == null || !product.isActive) return false;

    final activeList = await _dao.getActiveProductsOrderedByCreatedAt();
    final index = activeList.indexWhere((p) => p.id == product.id);
    if (index == -1) return false;

    return (index + 1) > limit;
  }
}

/// Extension helper pada model [Product] untuk pengecekan status kunci tier secara langsung
extension ProductTierExtension on Product {
  /// Mengembalikan true jika produk ini terkunci oleh kuota tier
  bool isLockedByTier({required int? limit, required int rankInActive}) {
    if (limit == null || !isActive) return false;
    return rankInActive > limit;
  }
}
