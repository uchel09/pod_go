import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/stock_dao.dart';

class StockRepository {
  final AppDatabase _db;
  final StockDao _stockDao;
  final ProductDao _productDao;

  StockRepository(this._db, this._stockDao, this._productDao);

  Future<List<StockMovement>> getAllMovements() => _stockDao.getAllMovements();

  Stream<List<StockMovement>> watchAllMovements() => _stockDao.watchAllMovements();

  Stream<List<StockMovement>> watchMovementsByProduct(int productId) =>
      _stockDao.watchMovementsByProduct(productId);

  Future<List<StockMovement>> getMovementsByProduct(int productId) =>
      _stockDao.getMovementsByProduct(productId);

  /// Mengambil halaman kartu stok dengan saldo berjalan (running balance)
  Future<List<StockCardEntry>> getStockCardPage({
    int limit = 30,
    int offset = 0,
    int? productId,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    return _stockDao.getStockCardPage(
      limit: limit,
      offset: offset,
      productId: productId,
      type: type,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );
  }

  /// Helper applyMovement:
  /// currentStock hanyalah cache dari stock_movements;
  /// setiap perubahan stok wajib dalam satu database.transaction()
  /// bersama pencatatan stock_movements.
  Future<void> applyMovement({
    required int productId,
    required String type, // sale / purchase / opname / void / adjustment
    required int qtyChange,
    String? refTable,
    int? refId,
    String? note,
    int? createdBy,
    String? uuid,
  }) async {
    await _db.transaction(() async {
      // 1. Catat stock movement
      await _stockDao.insertMovement(
        StockMovementsCompanion.insert(
          uuid: uuid ?? const Uuid().v4(),
          productId: productId,
          type: type,
          qtyChange: qtyChange,
          refTable: Value(refTable),
          refId: Value(refId),
          note: Value(note),
          createdBy: Value(createdBy),
        ),
      );

      // 2. Ambil product terkini & update cache currentStock
      final product = await _productDao.getProductById(productId);
      if (product == null) {
        throw StateError('Produk dengan ID $productId tidak ditemukan');
      }

      final newStock = product.currentStock + qtyChange;
      await _productDao.updateProductStock(productId, newStock);
    });
  }

  /// Penyesuaian stok manual (Prompt 10B)
  /// - Mode: 'add' (tambah stok) | 'set' (set stok utuh riil)
  /// - Alasan wajib: rusak, hilang, kadaluarsa, salah_input, lainnya
  /// - Jika 'lainnya', catatan wajib minimal 5 karakter
  /// - Selisih nol ditolak
  /// - Produk terkunci tier TETAP BISA disesuaikan stoknya
  Future<void> adjustStock({
    required int productId,
    required String mode, // 'add' | 'set'
    required int qty,
    String reason = 'lainnya', // rusak, hilang, kadaluarsa, salah_input, lainnya
    String? note,
    int? createdBy,
  }) async {
    // 1. Cek izin stock.adjust
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.stockAdjust)) {
        throw const AppException('Akses ditolak: Anda tidak memiliki izin penyesuaian stok.');
      }
    }

    // 2. Validasi alasan
    const validReasons = ['rusak', 'hilang', 'kadaluarsa', 'salah_input', 'lainnya'];
    final normalizedReason = reason.trim().toLowerCase();
    if (!validReasons.contains(normalizedReason)) {
      throw AppException('Alasan penyesuaian tidak valid: $reason');
    }

    final trimmedNote = (note ?? '').trim();
    if (normalizedReason == 'lainnya' && trimmedNote.length < 5) {
      throw const AppException('Untuk alasan "Lainnya", catatan wajib diisi minimal 5 karakter.');
    }

    final userId = createdBy ??
        (Get.isRegistered<AuthService>() ? AuthService.to.currentUser.value?.id : null);

    await _db.transaction(() async {
      final product = await _productDao.getProductById(productId);
      if (product == null) {
        throw AppException('Produk dengan ID $productId tidak ditemukan.');
      }

      final oldStock = product.currentStock;
      int qtyChange;
      int newStock;

      if (mode == 'add') {
        if (qty <= 0) {
          throw const AppException('Jumlah penambahan stok harus lebih dari 0.');
        }
        qtyChange = qty;
        newStock = oldStock + qtyChange;
      } else if (mode == 'set') {
        if (qty < 0) {
          throw const AppException('Target stok baru tidak boleh negatif.');
        }
        qtyChange = qty - oldStock;
        newStock = qty;
      } else {
        throw AppException('Mode penyesuaian tidak dikenal: $mode');
      }

      if (qtyChange == 0) {
        throw const AppException('Tidak ada perubahan stok.');
      }

      if (newStock < 0) {
        throw const AppException('Stok produk tidak boleh menjadi negatif.');
      }

      final fullNote = trimmedNote.isNotEmpty ? '[$normalizedReason] $trimmedNote' : '[$normalizedReason]';

      // 1. Simpan stock movement
      await _stockDao.insertMovement(
        StockMovementsCompanion.insert(
          uuid: const Uuid().v4(),
          productId: productId,
          type: 'adjustment',
          qtyChange: qtyChange,
          refTable: const Value('stock_adjustments'),
          refId: const Value(null),
          note: Value(fullNote),
          createdBy: Value(userId),
        ),
      );

      // 2. Update cache currentStock
      await _productDao.updateProductStock(productId, newStock);

      // 3. Catat jejak audit
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: AuditActions.stockAdjust,
          entity: 'products',
          entityId: productId,
          detail: {
            'productId': productId,
            'productName': product.name,
            'oldStock': oldStock,
            'newStock': newStock,
            'qtyChange': qtyChange,
            'mode': mode,
            'reason': normalizedReason,
            'note': trimmedNote,
          },
        );
      }
    });
  }
}
