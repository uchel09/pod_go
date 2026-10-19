import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/purchase_items.dart';
import '../tables/purchases.dart';

part 'purchase_dao.g.dart';

class PurchaseWithSupplier {
  final Purchase purchase;
  final Supplier? supplier;

  const PurchaseWithSupplier({
    required this.purchase,
    this.supplier,
  });

  String get supplierName => supplier?.name ?? 'Pemasok Umum';
}

class PurchaseDetailEntry {
  final Purchase purchase;
  final Supplier? supplier;
  final List<PurchaseItemDetail> items;

  const PurchaseDetailEntry({
    required this.purchase,
    this.supplier,
    required this.items,
  });

  String get supplierName => supplier?.name ?? 'Pemasok Umum';
}

class PurchaseItemDetail {
  final PurchaseItem item;
  final Product? product;

  const PurchaseItemDetail({
    required this.item,
    this.product,
  });

  String get productName => product?.name ?? 'Produk #${item.productId}';
  int get subtotal => item.qty * item.costPrice;
}

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

  Future<int> markPurchaseAsCancelled(int purchaseId) {
    return (update(purchases)..where((t) => t.id.equals(purchaseId))).write(
      PurchasesCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<PurchaseWithSupplier>> getPurchasesPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? supplierId,
    String? status,
    String? searchQuery,
  }) async {
    final query = select(purchases).join([
      leftOuterJoin(db.suppliers, db.suppliers.id.equalsExp(purchases.supplierId)),
    ]);

    if (startDate != null) {
      query.where(purchases.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(purchases.date.isSmallerOrEqualValue(endDate));
    }
    if (supplierId != null && supplierId > 0) {
      query.where(purchases.supplierId.equals(supplierId));
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      query.where(purchases.status.equals(status));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(purchases.refNo.like(term) | db.suppliers.name.like(term));
    }

    query.orderBy([
      OrderingTerm(expression: purchases.date, mode: OrderingMode.desc),
      OrderingTerm(expression: purchases.id, mode: OrderingMode.desc),
    ]);
    query.limit(limit, offset: offset);

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseWithSupplier(
        purchase: row.readTable(purchases),
        supplier: row.readTableOrNull(db.suppliers),
      );
    }).toList();
  }

  Stream<List<PurchaseWithSupplier>> watchPurchasesPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? supplierId,
    String? status,
    String? searchQuery,
  }) {
    final query = select(purchases).join([
      leftOuterJoin(db.suppliers, db.suppliers.id.equalsExp(purchases.supplierId)),
    ]);

    if (startDate != null) {
      query.where(purchases.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(purchases.date.isSmallerOrEqualValue(endDate));
    }
    if (supplierId != null && supplierId > 0) {
      query.where(purchases.supplierId.equals(supplierId));
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      query.where(purchases.status.equals(status));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(purchases.refNo.like(term) | db.suppliers.name.like(term));
    }

    query.orderBy([
      OrderingTerm(expression: purchases.date, mode: OrderingMode.desc),
      OrderingTerm(expression: purchases.id, mode: OrderingMode.desc),
    ]);
    query.limit(limit, offset: offset);

    return query.watch().map((rows) {
      return rows.map((row) {
        return PurchaseWithSupplier(
          purchase: row.readTable(purchases),
          supplier: row.readTableOrNull(db.suppliers),
        );
      }).toList();
    });
  }

  Future<PurchaseDetailEntry?> getPurchaseDetail(int purchaseId) async {
    final p = await (select(purchases)..where((t) => t.id.equals(purchaseId))).getSingleOrNull();
    if (p == null) return null;

    final supplier = await (select(db.suppliers)..where((t) => t.id.equals(p.supplierId))).getSingleOrNull();

    final itemQuery = select(purchaseItems).join([
      leftOuterJoin(products, products.id.equalsExp(purchaseItems.productId)),
    ])..where(purchaseItems.purchaseId.equals(purchaseId));

    final rows = await itemQuery.get();
    final items = rows.map((r) {
      return PurchaseItemDetail(
        item: r.readTable(purchaseItems),
        product: r.readTableOrNull(products),
      );
    }).toList();

    return PurchaseDetailEntry(
      purchase: p,
      supplier: supplier,
      items: items,
    );
  }
}
