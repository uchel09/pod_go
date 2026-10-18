import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/units.dart';

part 'unit_dao.g.dart';

@DriftAccessor(tables: [Units])
class UnitDao extends DatabaseAccessor<AppDatabase> with _$UnitDaoMixin {
  UnitDao(super.db);

  Future<List<Unit>> getAllUnits() => select(units).get();

  Stream<List<Unit>> watchAllUnits() => select(units).watch();

  Future<Unit?> getUnitById(int id) =>
      (select(units)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Unit?> getUnitByName(String name) =>
      (select(units)..where((t) => t.name.lower().equals(name.toLowerCase()))).getSingleOrNull();

  Future<Unit?> getUnitBySymbol(String symbol) =>
      (select(units)..where((t) => t.symbol.lower().equals(symbol.toLowerCase()))).getSingleOrNull();

  Future<int> insertUnit(UnitsCompanion unit) => into(units).insert(unit);

  Future<bool> updateUnit(UnitsCompanion unit) => update(units).replace(unit);

  Future<int> deleteUnit(int id) => (delete(units)..where((t) => t.id.equals(id))).go();
}

