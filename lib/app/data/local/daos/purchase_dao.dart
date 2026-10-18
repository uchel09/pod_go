import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/purchase_items.dart';
import '../tables/purchases.dart';

part 'purchase_dao.g.dart';

@DriftAccessor(tables: [Purchases, PurchaseItems, Products])
class PurchaseDao extends DatabaseAccessor<AppDatabase> with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  Future<List<Purchase>> getAllPurchases() => select(purchases).get();

  Stream<List<Purchase>> watchAllPurchases() => select(purchases).watch();

  Future<Purchase?> getPurchaseById(int id) =>
      (select(purchases)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertPurchase(PurchasesCompanion purchase) =>
      into(purchases).insert(purchase);

  Future<bool> updatePurchase(PurchasesCompanion purchase) =>
      update(purchases).replace(purchase);

  Future<int> insertPurchaseItem(PurchaseItemsCompanion item) =>
      into(purchaseItems).insert(item);

  Future<List<PurchaseItem>> getItemsByPurchaseId(int purchaseId) =>
      (select(purchaseItems)..where((t) => t.purchaseId.equals(purchaseId))).get();
}

