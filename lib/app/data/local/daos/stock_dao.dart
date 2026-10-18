import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/stock_movements.dart';

part 'stock_dao.g.dart';

@DriftAccessor(tables: [StockMovements, Products])
class StockDao extends DatabaseAccessor<AppDatabase> with _$StockDaoMixin {
  StockDao(super.db);

  Future<List<StockMovement>> getAllMovements() => select(stockMovements).get();

  Stream<List<StockMovement>> watchAllMovements() => select(stockMovements).watch();

  Stream<List<StockMovement>> watchMovementsByProduct(int productId) =>
      (select(stockMovements)..where((t) => t.productId.equals(productId))).watch();

  Future<int> insertMovement(StockMovementsCompanion movement) =>
      into(stockMovements).insert(movement);

  Future<List<StockMovement>> getMovementsByProduct(int productId) =>
      (select(stockMovements)..where((t) => t.productId.equals(productId))).get();
}

