import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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
}

