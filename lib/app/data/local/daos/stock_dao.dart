import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/stock_movements.dart';

part 'stock_dao.g.dart';

class StockCardEntry {
  final int id;
  final String uuid;
  final int productId;
  final String productName;
  final String type; // sale / purchase / opname / void / adjustment
  final int qtyChange;
  final int stockAfter;
  final String? refTable;
  final int? refId;
  final String? note;
  final int? createdBy;
  final String userName;
  final DateTime createdAt;

  const StockCardEntry({
    required this.id,
    required this.uuid,
    required this.productId,
    required this.productName,
    required this.type,
    required this.qtyChange,
    required this.stockAfter,
    this.refTable,
    this.refId,
    this.note,
    this.createdBy,
    required this.userName,
    required this.createdAt,
  });
}

@DriftAccessor(tables: [StockMovements, Products])
class StockDao extends DatabaseAccessor<AppDatabase> with _$StockDaoMixin {
  StockDao(super.db);

  Future<List<StockMovement>> getAllMovements() => select(stockMovements).get();

  Stream<List<StockMovement>> watchAllMovements() => select(stockMovements).watch();

  Stream<List<StockMovement>> watchMovementsByProduct(int productId) =>
      (select(stockMovements)..where((t) => t.productId.equals(productId))).watch();

  Future<int> insertMovement(StockMovementsCompanion movement) =>
      into(stockMovements).insert(movement);

  Future<List<StockMovement>> getMovementsByProduct(int productId) =>
      (select(stockMovements)..where((t) => t.productId.equals(productId))).get();

  /// Query Kartu Stok (running balance) menggunakan SQL Window Function:
  /// SUM(qty_change) OVER (PARTITION BY product_id ORDER BY created_at ASC, id ASC)
  Future<List<StockCardEntry>> getStockCardPage({
    int limit = 30,
    int offset = 0,
    int? productId,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (productId != null) {
      conditions.add('product_id = ?');
      variables.add(Variable<int>(productId));
    }
    if (type != null && type != 'all' && type.isNotEmpty) {
      conditions.add('type = ?');
      variables.add(Variable<String>(type));
    }
    if (startDate != null) {
      conditions.add('created_at >= ?');
      variables.add(Variable<DateTime>(startDate));
    }
    if (endDate != null) {
      conditions.add('created_at < ?');
      variables.add(Variable<DateTime>(endDate));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('(product_name LIKE ? OR note LIKE ?)');
      final term = '%${searchQuery.trim()}%';
      variables.add(Variable<String>(term));
      variables.add(Variable<String>(term));
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final sql = '''
      WITH movements_with_balance AS (
        SELECT 
          sm.id,
          sm.uuid,
          sm.product_id,
          p.name AS product_name,
          sm.type,
          sm.qty_change,
          CAST(SUM(sm.qty_change) OVER (
            PARTITION BY sm.product_id 
            ORDER BY sm.created_at ASC, sm.id ASC
          ) AS INTEGER) AS stock_after,
          sm.ref_table,
          sm.ref_id,
          sm.note,
          sm.created_by,
          COALESCE(u.display_name, 'Sistem') AS user_name,
          sm.created_at
        FROM stock_movements sm
        JOIN products p ON sm.product_id = p.id
        LEFT JOIN users u ON sm.created_by = u.id
      )
      SELECT * FROM movements_with_balance
      $whereClause
      ORDER BY created_at DESC, id DESC
      LIMIT ? OFFSET ?
    ''';

    variables.add(Variable<int>(limit));
    variables.add(Variable<int>(offset));

    final rows = await customSelect(
      sql,
      variables: variables,
      readsFrom: {stockMovements, products},
    ).get();

    return rows.map((r) {
      return StockCardEntry(
        id: r.read<int>('id'),
        uuid: r.read<String>('uuid'),
        productId: r.read<int>('product_id'),
        productName: r.read<String>('product_name'),
        type: r.read<String>('type'),
        qtyChange: r.read<int>('qty_change'),
        stockAfter: r.read<int>('stock_after'),
        refTable: r.readNullable<String>('ref_table'),
        refId: r.readNullable<int>('ref_id'),
        note: r.readNullable<String>('note'),
        createdBy: r.readNullable<int>('created_by'),
        userName: r.read<String>('user_name'),
        createdAt: r.read<DateTime>('created_at'),
      );
    }).toList();
  }
}
