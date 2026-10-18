import '../local/app_database.dart';
import '../local/daos/unit_dao.dart';

class UnitRepository {
  final UnitDao _dao;

  UnitRepository(this._dao);

  Future<List<Unit>> getAllUnits() => _dao.getAllUnits();
  Stream<List<Unit>> watchAllUnits() => _dao.watchAllUnits();
  Future<Unit?> getUnitById(int id) => _dao.getUnitById(id);
  Future<Unit?> getUnitByName(String name) => _dao.getUnitByName(name);
  Future<Unit?> getUnitBySymbol(String symbol) => _dao.getUnitBySymbol(symbol);
  Future<int> insertUnit(UnitsCompanion unit) => _dao.insertUnit(unit);
  Future<bool> updateUnit(UnitsCompanion unit) => _dao.updateUnit(unit);
  Future<int> deleteUnit(int id) => _dao.deleteUnit(id);
}

