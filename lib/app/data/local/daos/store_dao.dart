import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/stores.dart';

part 'store_dao.g.dart';

@DriftAccessor(tables: [Stores])
class StoreDao extends DatabaseAccessor<AppDatabase> with _$StoreDaoMixin {
  StoreDao(super.db);

  Future<Store?> getStore() => (select(stores)..limit(1)).getSingleOrNull();

  Stream<Store?> watchStore() => (select(stores)..limit(1)).watchSingleOrNull();

  Future<int> insertStore(StoresCompanion store) => into(stores).insert(store);

  Future<bool> updateStore(StoresCompanion store) {
    if (store.id.present) {
      return (update(stores)..where((t) => t.id.equals(store.id.value)))
          .write(store)
          .then((rows) => rows > 0);
    }
    return update(stores).replace(store);
  }

  Future<int> deleteStore(int id) => (delete(stores)..where((t) => t.id.equals(id))).go();
}

