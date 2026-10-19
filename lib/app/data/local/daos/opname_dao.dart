import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/stock_opname_items.dart';
import '../tables/stock_opnames.dart';

part 'opname_dao.g.dart';

class OpnameSummaryEntry {
  final StockOpname opname;
  final int totalItems;
  final int totalDifferenceItems;
  final String? creatorName;

  const OpnameSummaryEntry({
    required this.opname,
    required this.totalItems,
    required this.totalDifferenceItems,
    this.creatorName,
  });

  String get code => opname.code;
  DateTime get date => opname.date;
  String get status => opname.status;
  bool get isDraft => status == 'draft';
  bool get isFinal => status == 'final';
}

class OpnameItemWithProduct {
  final StockOpnameItem item;
  final Product product;
  final String? unitName;
  final String? categoryName;

  const OpnameItemWithProduct({
    required this.item,
    required this.product,
    this.unitName,
    this.categoryName,
  });

  int get id => item.id;
  int get productId => item.productId;
  int get systemQty => item.systemQty;
  int get countedQty => item.countedQty;
  bool get isCounted => item.countedQty >= 0;
  int get difference => isCounted ? (item.countedQty - item.systemQty) : 0;
  int get differenceValue => difference * product.costPrice;
}

class OpnameDetailEntry {
  final StockOpname opname;
  final List<OpnameItemWithProduct> items;
  final String? creatorName;

  const OpnameDetailEntry({
    required this.opname,
    required this.items,
    this.creatorName,
  });

  String get code => opname.code;
  DateTime get date => opname.date;
  String get status => opname.status;
  bool get isDraft => status == 'draft';
  bool get isFinal => status == 'final';

  int get totalItems => items.length;
  int get countedCount => items.where((i) => i.isCounted).length;
  int get uncountedCount => items.where((i) => !i.isCounted).length;
  int get diffCount => items.where((i) => i.isCounted && i.difference != 0).length;
  int get totalDiffValue => items.fold<int>(0, (sum, i) => sum + (i.isCounted ? i.differenceValue : 0));
}

@DriftAccessor(tables: [StockOpnames, StockOpnameItems, Products])
class OpnameDao extends DatabaseAccessor<AppDatabase> with _$OpnameDaoMixin {
  OpnameDao(super.db);

  Future<List<StockOpname>> getAllOpnames() => select(stockOpnames).get();

  Stream<List<StockOpname>> watchAllOpnames() => select(stockOpnames).watch();

  Future<StockOpname?> getOpnameById(int id) =>
      (select(stockOpnames)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<StockOpname?> getOpnameByUuid(String uuid) =>
      (select(stockOpnames)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Future<int> insertOpname(StockOpnamesCompanion opname) =>
      into(stockOpnames).insert(opname);

  Future<bool> updateOpname(StockOpnamesCompanion opname) =>
      update(stockOpnames).replace(opname);

  Future<int> deleteOpname(int id) async {
    return transaction(() async {
      await (delete(stockOpnameItems)..where((t) => t.opnameId.equals(id))).go();
      return (delete(stockOpnames)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Menghasilkan kode unik berurutan: OPN-YYYYMMDD-NN
  Future<String> generateNextOpnameCode(DateTime date) async {
    final dateStr = DateFormat('yyyyMMdd').format(date);
    final prefix = 'OPN-$dateStr-';

    final existing = await (select(stockOpnames)
          ..where((t) => t.code.like('$prefix%'))
          ..orderBy([(t) => OrderingTerm(expression: t.code, mode: OrderingMode.desc)]))
        .get();

    int maxNum = 0;
    for (final op in existing) {
      final suffix = op.code.replaceFirst(prefix, '');
      final num = int.tryParse(suffix);
      if (num != null && num > maxNum) {
        maxNum = num;
      }
    }

    final nextNum = (maxNum + 1).toString().padLeft(2, '0');
    return '$prefix$nextNum';
  }

  /// Mengambil daftar ringkasan sesi opname dengan pagination dan filter
  Future<List<OpnameSummaryEntry>> getOpnamesPaged({
    required int limit,
    int offset = 0,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final query = select(stockOpnames).join([
      leftOuterJoin(db.users, db.users.id.equalsExp(stockOpnames.createdBy)),
    ]);

    if (status != null && status.isNotEmpty && status != 'all') {
      query.where(stockOpnames.status.equals(status));
    }
    if (startDate != null) {
      query.where(stockOpnames.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(stockOpnames.date.isSmallerOrEqualValue(endDate));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(stockOpnames.code.like(term) | stockOpnames.note.like(term));
    }

    query.orderBy([
      OrderingTerm(expression: stockOpnames.date, mode: OrderingMode.desc),
      OrderingTerm(expression: stockOpnames.id, mode: OrderingMode.desc),
    ]);
    query.limit(limit, offset: offset);

    final rows = await query.get();
    if (rows.isEmpty) return [];

    final opnameList = rows.map((r) => r.readTable(stockOpnames)).toList();
    final opnameIds = opnameList.map((o) => o.id).toList();

    // Ambil statistik item untuk opnameIds
    final allItems = await (select(stockOpnameItems)
          ..where((t) => t.opnameId.isIn(opnameIds)))
        .get();

    final Map<int, List<StockOpnameItem>> itemsByOpname = {};
    for (final it in allItems) {
      itemsByOpname.putIfAbsent(it.opnameId, () => []).add(it);
    }

    return rows.map((row) {
      final op = row.readTable(stockOpnames);
      final user = row.readTableOrNull(db.users);
      final items = itemsByOpname[op.id] ?? [];

      final totalItems = items.length;
      final diffItems = items.where((i) => i.countedQty >= 0 && i.difference != 0).length;

      return OpnameSummaryEntry(
        opname: op,
        totalItems: totalItems,
        totalDifferenceItems: diffItems,
        creatorName: user?.displayName ?? user?.username,
      );
    }).toList();
  }

  /// Detail lengkap sesi opname dengan item dan produk
  Future<OpnameDetailEntry?> getOpnameDetail(int opnameId) async {
    final opnameQuery = select(stockOpnames).join([
      leftOuterJoin(db.users, db.users.id.equalsExp(stockOpnames.createdBy)),
    ])..where(stockOpnames.id.equals(opnameId));

    final opnameRow = await opnameQuery.getSingleOrNull();
    if (opnameRow == null) return null;

    final op = opnameRow.readTable(stockOpnames);
    final user = opnameRow.readTableOrNull(db.users);

    final itemsQuery = select(stockOpnameItems).join([
      innerJoin(products, products.id.equalsExp(stockOpnameItems.productId)),
      leftOuterJoin(db.units, db.units.id.equalsExp(products.unitId)),
      leftOuterJoin(db.categories, db.categories.id.equalsExp(products.categoryId)),
    ])
      ..where(stockOpnameItems.opnameId.equals(opnameId))
      ..orderBy([OrderingTerm(expression: products.name, mode: OrderingMode.asc)]);

    final itemRows = await itemsQuery.get();

    final items = itemRows.map((row) {
      return OpnameItemWithProduct(
        item: row.readTable(stockOpnameItems),
        product: row.readTable(products),
        unitName: row.readTableOrNull(db.units)?.name,
        categoryName: row.readTableOrNull(db.categories)?.name,
      );
    }).toList();

    return OpnameDetailEntry(
      opname: op,
      items: items,
      creatorName: user?.displayName ?? user?.username,
    );
  }

  Future<List<StockOpnameItem>> getItemsByOpnameId(int opnameId) =>
      (select(stockOpnameItems)..where((t) => t.opnameId.equals(opnameId))).get();

  Future<StockOpnameItem?> findItem(int opnameId, int productId) =>
      (select(stockOpnameItems)
            ..where((t) => t.opnameId.equals(opnameId) & t.productId.equals(productId)))
          .getSingleOrNull();

  Future<int> insertOpnameItem(StockOpnameItemsCompanion item) =>
      into(stockOpnameItems).insert(item);

  Future<int> updateOpnameItem(int id, StockOpnameItemsCompanion item) =>
      (update(stockOpnameItems)..where((t) => t.id.equals(id))).write(item);

  Future<int> deleteOpnameItem(int id) =>
      (delete(stockOpnameItems)..where((t) => t.id.equals(id))).go();

  Future<void> bulkInsertItems(List<StockOpnameItemsCompanion> items) async {
    await batch((batch) {
      batch.insertAll(stockOpnameItems, items);
    });
  }
}
