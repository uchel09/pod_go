import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sale_items.dart';
import '../tables/sale_return_items.dart';
import '../tables/sale_returns.dart';
import '../tables/sales.dart';
import '../tables/users.dart';

part 'sale_return_dao.g.dart';

class SaleReturnEntry {
  final SaleReturn saleReturn;
  final String cashierName;
  final String invoiceNo;
  final int itemCount;

  const SaleReturnEntry({
    required this.saleReturn,
    required this.cashierName,
    required this.invoiceNo,
    required this.itemCount,
  });
}

class SaleReturnDetail {
  final SaleReturn saleReturn;
  final List<SaleReturnItem> items;
  final String cashierName;
  final String invoiceNo;

  const SaleReturnDetail({
    required this.saleReturn,
    required this.items,
    required this.cashierName,
    required this.invoiceNo,
  });
}

@DriftAccessor(tables: [SaleReturns, SaleReturnItems, Sales, SaleItems, Products, Users])
class SaleReturnDao extends DatabaseAccessor<AppDatabase> with _$SaleReturnDaoMixin {
  SaleReturnDao(super.db);

  Future<int> insertReturn(SaleReturnsCompanion ret) =>
      into(saleReturns).insert(ret);

  Future<int> insertReturnItem(SaleReturnItemsCompanion item) =>
      into(saleReturnItems).insert(item);

  Future<SaleReturn?> getReturnById(int id) =>
      (select(saleReturns)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<SaleReturn?> getReturnByNo(String returnNo) =>
      (select(saleReturns)..where((t) => t.returnNo.equals(returnNo))).getSingleOrNull();

  Future<List<SaleReturn>> getReturnsBySaleId(int saleId) =>
      (select(saleReturns)
            ..where((t) => t.saleId.equals(saleId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<SaleReturnItem>> getItemsByReturnId(int returnId) =>
      (select(saleReturnItems)..where((t) => t.returnId.equals(returnId))).get();

  Future<List<SaleReturnItem>> getItemsByReturnIds(Iterable<int> returnIds) {
    if (returnIds.isEmpty) return Future.value(const []);
    return (select(saleReturnItems)..where((t) => t.returnId.isIn(returnIds))).get();
  }

  /// Menghitung jumlah retur yang cocok dengan awalan nomor retur (misal 'RTN-20261021-')
  Future<int> countReturnsByPrefix(String prefix) async {
    final count = countAll();
    final query = selectOnly(saleReturns)
      ..addColumns([count])
      ..where(saleReturns.returnNo.like('$prefix%'));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Menghitung total qty yang sudah diretur per sale_item_id untuk satu saleId
  Future<Map<int, int>> getReturnedQtyPerSaleItem(int saleId) async {
    final query = select(saleReturnItems).join([
      innerJoin(saleReturns, saleReturns.id.equalsExp(saleReturnItems.returnId)),
    ])..where(saleReturns.saleId.equals(saleId));

    final rows = await query.get();
    final result = <int, int>{};
    for (final row in rows) {
      final item = row.readTable(saleReturnItems);
      result[item.saleItemId] = (result[item.saleItemId] ?? 0) + item.qty;
    }
    return result;
  }

  /// Menghitung total nilai refund yang sudah dikeluarkan untuk satu transaksi
  Future<int> getTotalRefundAmountForSale(int saleId) async {
    final sumCol = saleReturns.total.sum();
    final query = selectOnly(saleReturns)
      ..addColumns([sumCol])
      ..where(saleReturns.saleId.equals(saleId));
    final row = await query.getSingle();
    return row.read(sumCol) ?? 0;
  }

  /// Menghitung total porsi refund kasbon yang sudah dipotongkan untuk satu transaksi
  Future<int> getTotalCreditRefundForSale(int saleId) async {
    final sumCol = saleReturns.creditRefund.sum();
    final query = selectOnly(saleReturns)
      ..addColumns([sumCol])
      ..where(saleReturns.saleId.equals(saleId));
    final row = await query.getSingle();
    return row.read(sumCol) ?? 0;
  }

  /// Memeriksa apakah transaksi memiliki riwayat retur
  Future<bool> hasReturnsForSale(int saleId) async {
    final count = countAll();
    final query = selectOnly(saleReturns)
      ..addColumns([count])
      ..where(saleReturns.saleId.equals(saleId));
    final row = await query.getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  /// Halaman riwayat retur dengan filter tanggal, pencarian, dan paginasi
  Future<List<SaleReturnEntry>> getReturnsPage({
    int limit = 30,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final query = select(saleReturns).join([
      innerJoin(sales, sales.id.equalsExp(saleReturns.saleId)),
      leftOuterJoin(users, users.id.equalsExp(saleReturns.createdBy)),
    ]);

    if (startDate != null) {
      query.where(saleReturns.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(saleReturns.createdAt.isSmallerThanValue(endDate));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      query.where(
        saleReturns.returnNo.like(q) |
            sales.invoiceNo.like(q) |
            saleReturns.reason.like(q),
      );
    }

    query.orderBy([OrderingTerm.desc(saleReturns.createdAt)]);
    query.limit(limit, offset: offset);

    final rows = await query.get();
    if (rows.isEmpty) return [];

    final returnIds = rows.map((r) => r.readTable(saleReturns).id).toList();
    final items = await getItemsByReturnIds(returnIds);

    final countsByReturn = <int, int>{};
    for (final it in items) {
      countsByReturn[it.returnId] = (countsByReturn[it.returnId] ?? 0) + it.qty;
    }

    return rows.map((row) {
      final ret = row.readTable(saleReturns);
      final sale = row.readTable(sales);
      final user = row.readTableOrNull(users);

      return SaleReturnEntry(
        saleReturn: ret,
        cashierName: user?.displayName ?? 'Kasir',
        invoiceNo: sale.invoiceNo,
        itemCount: countsByReturn[ret.id] ?? 0,
      );
    }).toList();
  }

  /// Detail lengkap satu transaksi retur
  Future<SaleReturnDetail?> getReturnDetail(int returnId) async {
    final ret = await getReturnById(returnId);
    if (ret == null) return null;

    final sale = await (select(sales)..where((t) => t.id.equals(ret.saleId))).getSingleOrNull();
    final user = await (select(users)..where((t) => t.id.equals(ret.createdBy))).getSingleOrNull();
    final items = await getItemsByReturnId(returnId);

    return SaleReturnDetail(
      saleReturn: ret,
      items: items,
      cashierName: user?.displayName ?? 'Kasir',
      invoiceNo: sale?.invoiceNo ?? '-',
    );
  }
}

