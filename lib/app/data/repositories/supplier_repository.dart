import 'package:drift/drift.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/supplier_dao.dart';

class SupplierRepository {
  final SupplierDao _dao;

  SupplierRepository(this._dao);

  Future<List<Supplier>> getAllSuppliers() => _dao.getAllSuppliers();
  Stream<List<Supplier>> watchAllSuppliers() => _dao.watchAllSuppliers();
  Future<List<Supplier>> searchSuppliers(String query) => _dao.searchSuppliers(query);
  Future<Supplier?> getSupplierById(int id) => _dao.getSupplierById(id);
  Future<Supplier> getOrCreateDefaultSupplier() => _dao.getOrCreateDefaultSupplier();

  String? _cleanString(String? val) {
    if (val == null) return null;
    final trimmed = val.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? address,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException('Nama supplier wajib diisi.');
    }

    final existing = await _dao.getSupplierByName(trimmedName);
    if (existing != null) {
      throw AppException('Nama supplier "$trimmedName" sudah digunakan.');
    }

    final id = await _dao.insertSupplier(
      SuppliersCompanion.insert(
        name: trimmedName,
        phone: Value(_cleanString(phone)),
        address: Value(_cleanString(address)),
      ),
    );

    return (await _dao.getSupplierById(id))!;
  }

  Future<Supplier> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? address,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException('Nama supplier wajib diisi.');
    }

    final existing = await _dao.getSupplierByName(trimmedName, excludeId: id);
    if (existing != null) {
      throw AppException('Nama supplier "$trimmedName" sudah digunakan.');
    }

    final target = await _dao.getSupplierById(id);
    if (target == null) {
      throw AppException('Supplier dengan ID $id tidak ditemukan.');
    }

    await _dao.updateSupplier(
      target.toCompanion(true).copyWith(
        name: Value(trimmedName),
        phone: Value(_cleanString(phone)),
        address: Value(_cleanString(address)),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return (await _dao.getSupplierById(id))!;
  }

  Future<void> deleteSupplier(int id) async {
    final purchaseCount = await _dao.countPurchasesBySupplierId(id);
    if (purchaseCount > 0) {
      throw const AppException(
        'Supplier tidak dapat dihapus karena sudah memiliki riwayat transaksi pembelian.',
      );
    }
    await _dao.deleteSupplier(id);
  }
}
