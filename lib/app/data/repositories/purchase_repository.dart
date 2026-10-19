import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/device_id_service.dart';
import '../local/app_database.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/purchase_dao.dart';
import '../local/daos/supplier_dao.dart';
import 'product_repository.dart';
import 'stock_repository.dart';

class PurchaseItemInput {
  final int productId;
  final int qty; // Wajib > 0
  final int costPrice; // Wajib >= 0 (Rupiah integer)
  final bool updateProductCost; // Toggle pembaruan harga beli produk

  const PurchaseItemInput({
    required this.productId,
    required this.qty,
    required this.costPrice,
    this.updateProductCost = true,
  });
}

class PurchaseRepository {
  final AppDatabase _db;
  final PurchaseDao _dao;
  final StockRepository _stockRepo;
  final ProductDao _productDao;
  final ProductRepository _productRepo;
  final SupplierDao _supplierDao;

  PurchaseRepository(
    this._db,
    this._dao,
    this._stockRepo,
    this._productDao,
    this._productRepo,
    this._supplierDao,
  );

  Future<List<Purchase>> getAllPurchases() => _dao.getAllPurchases();
  Stream<List<Purchase>> watchAllPurchases() => _dao.watchAllPurchases();
  Future<Purchase?> getPurchaseById(int id) => _dao.getPurchaseById(id);
  Future<List<PurchaseItem>> getItemsByPurchaseId(int purchaseId) =>
      _dao.getItemsByPurchaseId(purchaseId);
  Future<PurchaseDetailEntry?> getPurchaseDetail(int purchaseId) =>
      _dao.getPurchaseDetail(purchaseId);

  Future<List<PurchaseWithSupplier>> getPurchasesPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? supplierId,
    String? status,
    String? searchQuery,
  }) =>
      _dao.getPurchasesPage(
        limit: limit,
        offset: offset,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
        status: status,
        searchQuery: searchQuery,
      );

  Stream<List<PurchaseWithSupplier>> watchPurchasesPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? supplierId,
    String? status,
    String? searchQuery,
  }) =>
      _dao.watchPurchasesPage(
        limit: limit,
        offset: offset,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
        status: status,
        searchQuery: searchQuery,
      );

  /// Mencatat penerimaan barang/pembelian baru dalam SATU transaksi atomik.
  /// - Menambah baris `purchases` dan `purchase_items`
  /// - Menggerakkan stok bertipe `purchase` (qtyChange positif) via [StockRepository.applyMovement]
  /// - Memperbarui `costPrice` pada tabel produk bila toggle aktif (dan mencatat ke [AuditService])
  /// - Mencatat jejak audit `AuditActions.stockPurchaseReceive`
  Future<Purchase> receive({
    int? supplierId,
    String? refNo,
    DateTime? date,
    required List<PurchaseItemInput> items,
    bool updateCostPrice = true,
    int? createdBy,
  }) async {
    // 1. Validasi Gate Tier (Lisensi Semi-Premium ke atas)
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.purchases)) {
        throw const AppException(
          'Fitur Pembelian & Supplier memerlukan lisensi Semi-Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    // 2. Validasi Hak Akses Role (stock.purchase)
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.stockPurchase)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin mengelola pembelian (stock.purchase).',
          code: 'FORBIDDEN',
        );
      }
    }

    if (items.isEmpty) {
      throw const AppException('Penerimaan pembelian harus memiliki minimal 1 item barang.');
    }

    for (final item in items) {
      if (item.qty <= 0) {
        throw const AppException('Jumlah item dalam pembelian harus lebih dari 0.');
      }
      if (item.costPrice < 0) {
        throw const AppException('Harga beli item tidak boleh bernilai negatif.');
      }
    }

    // 3. Validasi status produk: Tidak boleh nonaktif dan tidak boleh terkunci tier
    final lockedProductIds = await _productRepo.getLockedProductIds();
    for (final item in items) {
      final product = await _productDao.getProductById(item.productId);
      if (product == null) {
        throw AppException('Produk dengan ID ${item.productId} tidak ditemukan.');
      }
      if (!product.isActive) {
        throw AppException(
          'Produk "${product.name}" sedang nonaktif dan tidak dapat ditambahkan ke pembelian.',
        );
      }
      if (lockedProductIds.contains(product.id)) {
        throw AppException(
          'Produk "${product.name}" terkunci oleh batas tier lisensi dan tidak dapat ditambahkan ke pembelian.',
        );
      }
    }

    // 4. Eksekusi dalam SATU database.transaction()
    return _db.transaction(() async {
      final purchaseDate = date ?? DateTime.now();
      final deviceId = Get.isRegistered<DeviceIdService>()
          ? DeviceIdService.to.deviceId
          : 'device-pos';
      final purchaseUuid = const Uuid().v4();

      // Pastikan supplierId valid, jika tidak pilih default
      int effectiveSupplierId;
      if (supplierId != null && supplierId > 0) {
        effectiveSupplierId = supplierId;
      } else {
        final defSupplier = await _supplierDao.getOrCreateDefaultSupplier();
        effectiveSupplierId = defSupplier.id;
      }

      final generatedRefNo = (refNo != null && refNo.trim().isNotEmpty)
          ? refNo.trim()
          : 'PO-${DateFormat('yyyyMMdd-HHmmss').format(purchaseDate)}';

      final total = items.fold<int>(0, (sum, it) => sum + (it.qty * it.costPrice));

      // 1. Simpan purchases
      final purchaseId = await _dao.insertPurchase(
        PurchasesCompanion(
          uuid: Value(purchaseUuid),
          deviceId: Value(deviceId),
          supplierId: Value(effectiveSupplierId),
          refNo: Value(generatedRefNo),
          date: Value(purchaseDate),
          total: Value(total),
          status: const Value('received'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 2. Simpan items, mutasi stok, dan update harga beli
      for (final item in items) {
        await _dao.insertPurchaseItem(
          PurchaseItemsCompanion(
            purchaseId: Value(purchaseId),
            productId: Value(item.productId),
            qty: Value(item.qty),
            costPrice: Value(item.costPrice),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        // Mutasi stok tipe 'purchase' (positif)
        await _stockRepo.applyMovement(
          productId: item.productId,
          type: 'purchase',
          qtyChange: item.qty,
          refTable: 'purchases',
          refId: purchaseId,
          note: 'Penerimaan pembelian $generatedRefNo',
          createdBy: createdBy,
        );

        // Perbarui harga beli produk ke master data jika toggle aktif
        if (updateCostPrice && item.updateProductCost) {
          final product = await _productDao.getProductById(item.productId);
          if (product != null && product.costPrice != item.costPrice) {
            final oldCost = product.costPrice;
            await _productDao.updateProduct(
              product.toCompanion(true).copyWith(
                costPrice: Value(item.costPrice),
                updatedAt: Value(DateTime.now()),
              ),
            );

            if (Get.isRegistered<AuditService>()) {
              AuditService.to.log(
                action: AuditActions.productPriceChange,
                entity: 'products',
                entityId: product.id,
                detail: {
                  'productName': product.name,
                  'oldPrice': oldCost,
                  'newPrice': item.costPrice,
                  'type': 'costPrice',
                  'diff': {
                    'costPrice': {'old': oldCost, 'new': item.costPrice},
                  },
                },
              );
            }
          }
        }
      }

      // 3. Catat jejak audit penerimaan pembelian
      final supplier = await _supplierDao.getSupplierById(effectiveSupplierId);
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: AuditActions.stockPurchaseReceive,
          entity: 'purchases',
          entityId: purchaseId,
          detail: {
            'purchaseId': purchaseId,
            'refNo': generatedRefNo,
            'supplierName': supplier?.name ?? 'Pemasok Umum',
            'total': total,
            'itemCount': items.length,
          },
        );
      }

      return (await _dao.getPurchaseById(purchaseId))!;
    });
  }

  /// Membatalkan transaksi pembelian yang sudah diterima.
  /// - Status diubah menjadi 'cancelled' (data tidak dihapus)
  /// - Mengembalikan stok melalui mutasi type 'adjustment' (negatif) via [StockRepository.applyMovement]
  /// - Bila stok produk saat ini tidak mencukupi untuk dibalikkan, seluruh pembatalan ditolak
  /// - Mencegah pembatalan dua kali
  /// - CATATAN PENTING: Pembatalan tidak mengembalikan costPrice produk (sesuai PROJECT_RULES.md)
  Future<Purchase> cancelPurchase({
    required int purchaseId,
    required String reason,
    int? cancelledBy,
  }) async {
    // 1. Validasi Gate Tier (Lisensi Semi-Premium ke atas)
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.purchases)) {
        throw const AppException(
          'Fitur Pembelian & Supplier memerlukan lisensi Semi-Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    // 2. Validasi Hak Akses Role (stock.purchase)
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.stockPurchase)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin membatalkan pembelian (stock.purchase).',
          code: 'FORBIDDEN',
        );
      }
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.length < 5) {
      throw const AppException('Alasan pembatalan pembelian wajib diisi minimal 5 karakter.');
    }

    return _db.transaction(() async {
      final purchase = await _dao.getPurchaseById(purchaseId);
      if (purchase == null) {
        throw AppException('Data pembelian dengan ID $purchaseId tidak ditemukan.');
      }

      if (purchase.status == 'cancelled') {
        throw const AppException('Pembelian ini sudah dibatalkan sebelumnya.');
      }

      final items = await _dao.getItemsByPurchaseId(purchaseId);

      // Cek apakah stok fisik produk saat ini cukup untuk ditarik kembali
      for (final item in items) {
        final product = await _productDao.getProductById(item.productId);
        if (product == null) continue;
        if (product.currentStock < item.qty) {
          throw AppException(
            'Pembatalan ditolak: Stok produk "${product.name}" saat ini (${product.currentStock}) tidak mencukupi untuk dibalikkan (${item.qty}).',
          );
        }
      }

      // Ubah status transaksi menjadi 'cancelled'
      await _dao.updatePurchase(
        purchase.toCompanion(true).copyWith(
          status: const Value('cancelled'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Kembalikan stok produk via movement type 'adjustment' (negatif)
      // Catatan: costPrice produk yang telah diubah TIDAK dibalikkan
      for (final item in items) {
        await _stockRepo.applyMovement(
          productId: item.productId,
          type: 'adjustment',
          qtyChange: -item.qty,
          refTable: 'purchases',
          refId: purchaseId,
          note: 'Pembatalan pembelian ${purchase.refNo}: $trimmedReason',
          createdBy: cancelledBy,
        );
      }

      // Catat jejak audit pembatalan
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: AuditActions.stockPurchaseCancel,
          entity: 'purchases',
          entityId: purchaseId,
          detail: {
            'purchaseId': purchaseId,
            'refNo': purchase.refNo,
            'reason': trimmedReason,
          },
        );
      }

      return (await _dao.getPurchaseById(purchaseId))!;
    });
  }
}
