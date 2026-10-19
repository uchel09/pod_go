import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/suppliers.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<List<Supplier>> getAllSuppliers() =>
      (select(suppliers)..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)])).get();

  Stream<List<Supplier>> watchAllSuppliers() =>
      (select(suppliers)..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)])).watch();

  Future<List<Supplier>> searchSuppliers(String query) {
    final term = '%${query.trim()}%';
    return (select(suppliers)
          ..where((t) => t.name.like(term) | t.phone.like(term) | t.address.like(term))
          ..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)]))
        .get();
  }

  Future<Supplier?> getSupplierById(int id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Supplier?> getSupplierByName(String name, {int? excludeId}) {
    final query = select(suppliers)..where((t) => t.name.lower().equals(name.toLowerCase().trim()));
    if (excludeId != null) {
      query.where((t) => t.id.equals(excludeId).not());
    }
    return query.getSingleOrNull();
  }

  Future<int> insertSupplier(SuppliersCompanion supplier) =>
      into(suppliers).insert(supplier);

  Future<bool> updateSupplier(SuppliersCompanion supplier) =>
      update(suppliers).replace(supplier);

  Future<int> deleteSupplier(int id) =>
      (delete(suppliers)..where((t) => t.id.equals(id))).go();

  Future<int> countPurchasesBySupplierId(int supplierId) async {
    final countExp = db.purchases.id.count();
    final query = selectOnly(db.purchases)
      ..addColumns([countExp])
      ..where(db.purchases.supplierId.equals(supplierId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<Supplier> getOrCreateDefaultSupplier() async {
    final existing = await getSupplierByName('Pemasok Umum');
    if (existing != null) return existing;

    final id = await insertSupplier(
      const SuppliersCompanion(
        name: Value('Pemasok Umum'),
        phone: Value('-'),
        address: Value('-'),
      ),
    );
    return (await getSupplierById(id))!;
  }
}
