import '../local/app_database.dart';
import '../local/daos/supplier_dao.dart';

class SupplierRepository {
  final SupplierDao _dao;

  SupplierRepository(this._dao);

  Future<List<Supplier>> getAllSuppliers() => _dao.getAllSuppliers();
  Stream<List<Supplier>> watchAllSuppliers() => _dao.watchAllSuppliers();
  Future<Supplier?> getSupplierById(int id) => _dao.getSupplierById(id);
  Future<int> insertSupplier(SuppliersCompanion supplier) => _dao.insertSupplier(supplier);
  Future<bool> updateSupplier(SuppliersCompanion supplier) => _dao.updateSupplier(supplier);
  Future<int> deleteSupplier(int id) => _dao.deleteSupplier(id);
}

