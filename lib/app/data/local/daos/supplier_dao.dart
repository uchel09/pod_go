import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/suppliers.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<List<Supplier>> getAllSuppliers() => select(suppliers).get();

  Stream<List<Supplier>> watchAllSuppliers() => select(suppliers).watch();

  Future<Supplier?> getSupplierById(int id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertSupplier(SuppliersCompanion supplier) =>
      into(suppliers).insert(supplier);

  Future<bool> updateSupplier(SuppliersCompanion supplier) =>
      update(suppliers).replace(supplier);

  Future<int> deleteSupplier(int id) =>
      (delete(suppliers)..where((t) => t.id.equals(id))).go();
}

