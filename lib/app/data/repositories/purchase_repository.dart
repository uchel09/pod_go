import '../local/app_database.dart';
import '../local/daos/purchase_dao.dart';

class PurchaseRepository {
  final PurchaseDao _dao;

  PurchaseRepository(this._dao);

  Future<List<Purchase>> getAllPurchases() => _dao.getAllPurchases();
  Stream<List<Purchase>> watchAllPurchases() => _dao.watchAllPurchases();
  Future<Purchase?> getPurchaseById(int id) => _dao.getPurchaseById(id);
  Future<int> insertPurchase(PurchasesCompanion purchase) => _dao.insertPurchase(purchase);
  Future<bool> updatePurchase(PurchasesCompanion purchase) => _dao.updatePurchase(purchase);
  Future<int> insertPurchaseItem(PurchaseItemsCompanion item) => _dao.insertPurchaseItem(item);
  Future<List<PurchaseItem>> getItemsByPurchaseId(int purchaseId) => _dao.getItemsByPurchaseId(purchaseId);
}

