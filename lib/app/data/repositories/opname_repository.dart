import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/device_id_service.dart';
import '../local/app_database.dart';
import '../local/daos/opname_dao.dart';
import '../local/daos/product_dao.dart';
import 'stock_repository.dart';

class OpnameRepository {
  final AppDatabase _db;
  final OpnameDao _dao;
  final StockRepository _stockRepo;
  final ProductDao _productDao;

  OpnameRepository(
    this._db,
    this._dao,
    this._stockRepo,
    this._productDao,
  );

  /// Memvalidasi hak akses dan gate fitur tier untuk stock opname
  void _assertAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.stockOpname)) {
        throw const AppException(
          'Fitur Stock Opname memerlukan lisensi Semi-Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.stockOpname)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin mengelola Stock Opname (stock.opname).',
          code: 'FORBIDDEN',
        );
      }
    }
  }

  /// Membuat sesi Stock Opname baru dalam status draft
  Future<StockOpname> createOpname({
    DateTime? date,
    String? note,
  }) async {
    _assertAccess();

    final opnameDate = date ?? DateTime.now();
    final deviceId = Get.isRegistered<DeviceIdService>()
        ? DeviceIdService.to.deviceId
        : 'device-local';

    final creatorId = Get.isRegistered<AuthService>()
        ? AuthService.to.currentUser.value?.id
        : null;

    final code = await _dao.generateNextOpnameCode(opnameDate);
    final opnameUuid = const Uuid().v4();

    final id = await _dao.insertOpname(
      StockOpnamesCompanion(
        uuid: Value(opnameUuid),
        deviceId: Value(deviceId),
        code: Value(code),
        date: Value(opnameDate),
        status: const Value('draft'),
        note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
        createdBy: Value(creatorId),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return (await _dao.getOpnameById(id))!;
  }

  /// Mengambil daftar ringkasan sesi opname dengan pagination
  Future<List<OpnameSummaryEntry>> getOpnamesPaged({
    required int limit,
    int offset = 0,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    return _dao.getOpnamesPaged(
      limit: limit,
      offset: offset,
      status: status,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );
  }

  Future<StockOpname?> getOpnameById(int id) => _dao.getOpnameById(id);

  Future<OpnameDetailEntry?> getOpnameDetail(int id) => _dao.getOpnameDetail(id);

  /// Menambah atau menambah (+1) hitungan produk pada sesi opname draft
  Future<void> addOrIncrementItem({
    required int opnameId,
    required int productId,
    int qty = 1,
  }) async {
    _assertAccess();

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) throw AppException('Sesi opname #$opnameId tidak ditemukan.');
    if (opname.status != 'draft') {
      throw const AppException('Sesi opname sudah final dan tidak dapat diubah.');
    }

    final product = await _productDao.getProductById(productId);
    if (product == null) throw AppException('Produk #$productId tidak ditemukan.');

    final existingItem = await _dao.findItem(opnameId, productId);
    if (existingItem != null) {
      final newCounted = existingItem.countedQty < 0
          ? qty
          : existingItem.countedQty + qty;
      final diff = newCounted - existingItem.systemQty;

      await _dao.updateOpnameItem(
        existingItem.id,
        StockOpnameItemsCompanion(
          countedQty: Value(newCounted),
          difference: Value(diff),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      final systemQty = product.currentStock;
      final diff = qty - systemQty;

      await _dao.insertOpnameItem(
        StockOpnameItemsCompanion(
          opnameId: Value(opnameId),
          productId: Value(productId),
          systemQty: Value(systemQty),
          countedQty: Value(qty),
          difference: Value(diff),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Mengubah jumlah hitungan fisik secara langsung (input angka / stepper)
  Future<void> updateItemCount({
    required int opnameId,
    required int itemId,
    required int countedQty,
  }) async {
    _assertAccess();

    if (countedQty < 0) {
      throw const AppException('Jumlah hitungan fisik tidak boleh negatif.');
    }

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) throw AppException('Sesi opname #$opnameId tidak ditemukan.');
    if (opname.status != 'draft') {
      throw const AppException('Sesi opname sudah final dan tidak dapat diubah.');
    }

    final items = await _dao.getItemsByOpnameId(opnameId);
    final targetItem = items.firstWhereOrNull((i) => i.id == itemId);
    if (targetItem == null) throw AppException('Item opname #$itemId tidak ditemukan.');

    final diff = countedQty - targetItem.systemQty;

    await _dao.updateOpnameItem(
      itemId,
      StockOpnameItemsCompanion(
        countedQty: Value(countedQty),
        difference: Value(diff),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Memuat semua produk aktif ke dalam sesi opname (countedQty = -1: belum dihitung)
  Future<int> loadAllActiveProducts(int opnameId) async {
    _assertAccess();

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) throw AppException('Sesi opname #$opnameId tidak ditemukan.');
    if (opname.status != 'draft') {
      throw const AppException('Sesi opname sudah final dan tidak dapat diubah.');
    }

    final activeProducts = await (_db.select(_db.products)
          ..where((t) => t.isActive.equals(true)))
        .get();

    final existingItems = await _dao.getItemsByOpnameId(opnameId);
    final existingProductIds = existingItems.map((i) => i.productId).toSet();

    final toInsert = <StockOpnameItemsCompanion>[];
    for (final p in activeProducts) {
      if (!existingProductIds.contains(p.id)) {
        toInsert.add(
          StockOpnameItemsCompanion(
            opnameId: Value(opnameId),
            productId: Value(p.id),
            systemQty: Value(p.currentStock),
            countedQty: const Value(-1), // Belum dihitung
            difference: const Value(0),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }

    if (toInsert.isNotEmpty) {
      await _dao.bulkInsertItems(toInsert);
    }

    return toInsert.length;
  }

  /// Memuat produk aktif berdasarkan kategori ke sesi opname
  Future<int> loadProductsByCategory({
    required int opnameId,
    required int categoryId,
  }) async {
    _assertAccess();

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) throw AppException('Sesi opname #$opnameId tidak ditemukan.');
    if (opname.status != 'draft') {
      throw const AppException('Sesi opname sudah final dan tidak dapat diubah.');
    }

    final products = await (_db.select(_db.products)
          ..where((t) => t.isActive.equals(true) & t.categoryId.equals(categoryId)))
        .get();

    final existingItems = await _dao.getItemsByOpnameId(opnameId);
    final existingProductIds = existingItems.map((i) => i.productId).toSet();

    final toInsert = <StockOpnameItemsCompanion>[];
    for (final p in products) {
      if (!existingProductIds.contains(p.id)) {
        toInsert.add(
          StockOpnameItemsCompanion(
            opnameId: Value(opnameId),
            productId: Value(p.id),
            systemQty: Value(p.currentStock),
            countedQty: const Value(-1),
            difference: const Value(0),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }

    if (toInsert.isNotEmpty) {
      await _dao.bulkInsertItems(toInsert);
    }

    return toInsert.length;
  }

  /// Menghapus satu item dari daftar hitung draft
  Future<void> deleteItem({
    required int opnameId,
    required int itemId,
  }) async {
    _assertAccess();

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) throw AppException('Sesi opname #$opnameId tidak ditemukan.');
    if (opname.status != 'draft') {
      throw const AppException('Sesi opname sudah final dan tidak dapat diubah.');
    }

    await _dao.deleteOpnameItem(itemId);
  }

  /// Menghapus sesi opname draft
  Future<void> deleteOpname(int opnameId) async {
    _assertAccess();

    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) return;

    if (opname.status == 'final') {
      throw const AppException('Sesi Stock Opname yang sudah final tidak dapat dihapus.');
    }

    await _dao.deleteOpname(opnameId);
  }

  /// Menghitung ulang systemQty dari currentStock terkini tiap produk untuk review
  Future<OpnameDetailEntry?> recalculateReview(int opnameId) async {
    final opname = await _dao.getOpnameById(opnameId);
    if (opname == null) return null;

    if (opname.status == 'draft') {
      final items = await _dao.getItemsByOpnameId(opnameId);
      for (final it in items) {
        final p = await _productDao.getProductById(it.productId);
        if (p != null && p.currentStock != it.systemQty) {
          final diff = it.countedQty >= 0 ? (it.countedQty - p.currentStock) : 0;
          await _dao.updateOpnameItem(
            it.id,
            StockOpnameItemsCompanion(
              systemQty: Value(p.currentStock),
              difference: Value(diff),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
    }

    return _dao.getOpnameDetail(opnameId);
  }

  /// Memfinalisasi Stock Opname dalam SATU transaksi database atomik:
  /// - Memastikan status masih draft (cegah final ganda)
  /// - Menghitung ulang systemQty dari stok terkini
  /// - Menyesuaikan stok via StockRepository.applyMovement (type 'opname') untuk selisih != 0
  /// - Mengubah status menjadi final
  /// - Mencatat jejak audit
  Future<StockOpname> finalize({
    required int opnameId,
    bool treatUncountedAsZero = false,
    String? note,
  }) async {
    _assertAccess();

    return await _db.transaction(() async {
      final opname = await _dao.getOpnameById(opnameId);
      if (opname == null) {
        throw AppException('Sesi Stock Opname #$opnameId tidak ditemukan.');
      }
      if (opname.status != 'draft') {
        throw const AppException(
          'Sesi Stock Opname sudah difinalisasi atau tidak dapat diubah.',
          code: 'ALREADY_FINALIZED',
        );
      }

      final items = await _dao.getItemsByOpnameId(opnameId);
      if (items.isEmpty) {
        throw const AppException('Tidak ada item produk dalam sesi opname ini.');
      }

      int totalDiffItems = 0;
      int totalDiffValue = 0;

      for (final item in items) {
        final product = await _productDao.getProductById(item.productId);
        if (product == null) continue;

        // Ambil stok sistem terkini saat ini
        final currentSystemQty = product.currentStock;
        int effectiveCountedQty = item.countedQty;

        if (effectiveCountedQty < 0) {
          if (treatUncountedAsZero) {
            effectiveCountedQty = 0;
          } else {
            // Dilewati: tidak diubah dan tidak dibuat movement stok
            await _dao.updateOpnameItem(
              item.id,
              StockOpnameItemsCompanion(
                systemQty: Value(currentSystemQty),
                countedQty: const Value(-1),
                difference: const Value(0),
                updatedAt: Value(DateTime.now()),
              ),
            );
            continue;
          }
        }

        final diff = effectiveCountedQty - currentSystemQty;

        // Simpan snapshot final
        await _dao.updateOpnameItem(
          item.id,
          StockOpnameItemsCompanion(
            systemQty: Value(currentSystemQty),
            countedQty: Value(effectiveCountedQty),
            difference: Value(diff),
            updatedAt: Value(DateTime.now()),
          ),
        );

        // Jika selisih != 0, buat movement type opname via StockRepository
        if (diff != 0) {
          totalDiffItems++;
          totalDiffValue += (diff * product.costPrice);

          await _stockRepo.applyMovement(
            productId: item.productId,
            type: 'opname',
            qtyChange: diff,
            refTable: 'stock_opnames',
            refId: opname.id,
            note: 'Stock Opname ${opname.code}',
            createdBy: opname.createdBy,
          );
        }
      }

      // Update status menjadi final
      await _dao.updateOpname(
        opname.toCompanion(true).copyWith(
          status: const Value('final'),
          note: note != null
              ? Value(note.trim().isEmpty ? null : note.trim())
              : opname.note != null
                  ? Value(opname.note)
                  : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Jejak Audit
      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.stockOpnameFinalize,
          entity: 'stock_opnames',
          entityId: opname.id,
          detail: {
            'code': opname.code,
            'totalItems': items.length,
            'diffCount': totalDiffItems,
            'totalDiffValue': totalDiffValue,
          },
        );
      }

      return (await _dao.getOpnameById(opnameId))!;
    });
  }
}
