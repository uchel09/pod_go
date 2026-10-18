import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/stock_opname_items.dart';
import '../tables/stock_opnames.dart';

part 'opname_dao.g.dart';

@DriftAccessor(tables: [StockOpnames, StockOpnameItems, Products])
class OpnameDao extends DatabaseAccessor<AppDatabase> with _$OpnameDaoMixin {
  OpnameDao(super.db);

  Future<List<StockOpname>> getAllOpnames() => select(stockOpnames).get();

  Stream<List<StockOpname>> watchAllOpnames() => select(stockOpnames).watch();

  Future<StockOpname?> getOpnameById(int id) =>
      (select(stockOpnames)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertOpname(StockOpnamesCompanion opname) =>
      into(stockOpnames).insert(opname);

  Future<bool> updateOpname(StockOpnamesCompanion opname) =>
      update(stockOpnames).replace(opname);

  Future<int> insertOpnameItem(StockOpnameItemsCompanion item) =>
      into(stockOpnameItems).insert(item);

  Future<List<StockOpnameItem>> getItemsByOpnameId(int opnameId) =>
      (select(stockOpnameItems)..where((t) => t.opnameId.equals(opnameId))).get();
}

