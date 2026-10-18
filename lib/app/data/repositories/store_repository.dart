import '../local/app_database.dart';
import '../local/daos/store_dao.dart';

class StoreRepository {
  final StoreDao _dao;

  StoreRepository(this._dao);

  Future<Store?> getStore() => _dao.getStore();
  Stream<Store?> watchStore() => _dao.watchStore();
  Future<int> insertStore(StoresCompanion store) => _dao.insertStore(store);
  Future<bool> updateStore(StoresCompanion store) => _dao.updateStore(store);
  Future<int> deleteStore(int id) => _dao.deleteStore(id);
}

