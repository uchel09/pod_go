import '../local/app_database.dart';
import '../local/daos/opname_dao.dart';

class OpnameRepository {
  final OpnameDao _dao;

  OpnameRepository(this._dao);

  Future<List<StockOpname>> getAllOpnames() => _dao.getAllOpnames();
  Stream<List<StockOpname>> watchAllOpnames() => _dao.watchAllOpnames();
  Future<StockOpname?> getOpnameById(int id) => _dao.getOpnameById(id);
  Future<int> insertOpname(StockOpnamesCompanion opname) => _dao.insertOpname(opname);
  Future<bool> updateOpname(StockOpnamesCompanion opname) => _dao.updateOpname(opname);
  Future<int> insertOpnameItem(StockOpnameItemsCompanion item) => _dao.insertOpnameItem(item);
  Future<List<StockOpnameItem>> getItemsByOpnameId(int opnameId) => _dao.getItemsByOpnameId(opnameId);
}

