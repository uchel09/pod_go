import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/payments.dart';
import '../tables/products.dart';
import '../tables/sale_items.dart';
import '../tables/sales.dart';

part 'sale_dao.g.dart';

@DriftAccessor(tables: [Sales, SaleItems, Payments, Products])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(super.db);

  Future<List<Sale>> getAllSales() => select(sales).get();

  Stream<List<Sale>> watchAllSales() => select(sales).watch();

  Future<Sale?> getSaleById(int id) =>
      (select(sales)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Sale?> getSaleByInvoice(String invoiceNo) =>
      (select(sales)..where((t) => t.invoiceNo.equals(invoiceNo))).getSingleOrNull();

  Future<int> insertSale(SalesCompanion sale) => into(sales).insert(sale);

  Future<bool> updateSale(SalesCompanion sale) => update(sales).replace(sale);

  Future<int> insertSaleItem(SaleItemsCompanion item) => into(saleItems).insert(item);

  Future<List<SaleItem>> getItemsBySaleId(int saleId) =>
      (select(saleItems)..where((t) => t.saleId.equals(saleId))).get();

  Future<int> insertPayment(PaymentsCompanion payment) => into(payments).insert(payment);

  Future<List<Payment>> getPaymentsBySaleId(int saleId) =>
      (select(payments)..where((t) => t.saleId.equals(saleId))).get();

  Future<int> countSalesByPrefix(String prefix) async {
    final countExp = sales.id.count();
    final query = selectOnly(sales)
      ..addColumns([countExp])
      ..where(sales.invoiceNo.like('$prefix%'));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<int> markSaleAsVoid({
    required int saleId,
    required String reason,
    required int? voidedBy,
    required DateTime voidedAt,
  }) {
    return (update(sales)..where((t) => t.id.equals(saleId))).write(
      SalesCompanion(
        status: const Value('void'),
        voidReason: Value(reason),
        voidedBy: Value(voidedBy),
        voidedAt: Value(voidedAt),
        updatedAt: Value(voidedAt),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Riwayat transaksi
  // ---------------------------------------------------------------------------

  /// Satu halaman transaksi, terbaru di atas (created_at DESC, id DESC).
  ///
  /// Memakai keyset pagination ([after]) alih-alih OFFSET agar halaman berikutnya
  /// tetap stabil walau ada transaksi baru masuk dan tidak makin lambat di data besar.
  Future<List<Sale>> getSalesPage({
    required int limit,
    SalesCursor? after,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? searchQuery,
  }) {
    final query = select(sales)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);

    if (startDate != null) {
      query.where((t) => t.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.createdAt.isSmallerThanValue(endDate));
    }
    if (status != null && status != 'all' && status.isNotEmpty) {
      query.where((t) => t.status.equals(status));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where((t) => t.invoiceNo.like(term));
    }

    if (after != null) {
      query.where(
        (t) =>
            t.createdAt.isSmallerThanValue(after.createdAt) |
            (t.createdAt.equals(after.createdAt) & t.id.isSmallerThanValue(after.id)),
      );
    }
    return query.get();
  }

  /// Semua pembayaran untuk sekumpulan transaksi dalam SATU query (hindari N+1).
  Future<List<Payment>> getPaymentsBySaleIds(Iterable<int> saleIds) {
    final ids = saleIds.toList();
    if (ids.isEmpty) return Future.value(const <Payment>[]);
    return (select(payments)..where((t) => t.saleId.isIn(ids))).get();
  }

  /// Nama tampilan kasir untuk sekumpulan id user dalam satu query.
  Future<Map<int, String>> getUserDisplayNames(Set<int> userIds) async {
    if (userIds.isEmpty) return const <int, String>{};
    final placeholders = List.filled(userIds.length, '?').join(', ');
    final rows = await customSelect(
      'SELECT id, display_name FROM users WHERE id IN ($placeholders)',
      variables: [for (final id in userIds) Variable<int>(id)],
    ).get();
    return {
      for (final row in rows) row.read<int>('id'): row.read<String>('display_name'),
    };
  }

  /// Ringkasan per hari (jumlah transaksi + omzet) lewat query agregat.
  ///
  /// Pengelompokan memakai tanggal LOKAL perangkat (`localtime`), bukan UTC, sehingga
  /// transaksi pukul 23:59 dan 00:01 jatuh ke hari yang benar. Rentang [from, to)
  /// membatasi baris yang dipindai (memanfaatkan indeks sales_created_at_idx).
  /// Hanya transaksi berstatus `completed` yang dihitung sebagai omzet (void tidak dihitung).
  Future<List<DailySalesSummary>> getDailySummaries({
    required DateTime from,
    required DateTime to,
    String? status,
    String? searchQuery,
  }) async {
    final conditions = <String>['created_at >= ? AND created_at < ?'];
    final variables = <Variable>[Variable<DateTime>(from), Variable<DateTime>(to)];

    if (status != null && status != 'all' && status.isNotEmpty) {
      conditions.add('status = ?');
      variables.add(Variable<String>(status));
    } else if (status == null) {
      conditions.add("status = 'completed'");
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('invoice_no LIKE ?');
      variables.add(Variable<String>('%${searchQuery.trim()}%'));
    }

    final whereClause = conditions.join(' AND ');

    final rows = await customSelect(
      "SELECT strftime('%Y-%m-%d', created_at, 'unixepoch', 'localtime') AS day, "
      'COUNT(*) AS tx_count, '
      "COALESCE(SUM(CASE WHEN status = 'completed' THEN total ELSE 0 END), 0) AS total_sum "
      'FROM sales '
      'WHERE $whereClause '
      'GROUP BY day '
      'ORDER BY day DESC',
      variables: variables,
      readsFrom: {sales},
    ).get();

    return rows
        .map(
          (row) => DailySalesSummary(
            day: row.read<String>('day'),
            transactionCount: row.read<int>('tx_count'),
            totalRevenue: row.read<int>('total_sum'),
          ),
        )
        .toList();
  }

  /// Ringkasan agregat keseluruhan filter aktif untuk total di atas list riwayat.
  Future<DailySalesSummary> getAggregateSummary({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? searchQuery,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (startDate != null) {
      conditions.add('created_at >= ?');
      variables.add(Variable<DateTime>(startDate));
    }
    if (endDate != null) {
      conditions.add('created_at < ?');
      variables.add(Variable<DateTime>(endDate));
    }
    if (status != null && status != 'all' && status.isNotEmpty) {
      conditions.add('status = ?');
      variables.add(Variable<String>(status));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('invoice_no LIKE ?');
      variables.add(Variable<String>('%${searchQuery.trim()}%'));
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final rows = await customSelect(
      'SELECT COUNT(*) AS tx_count, '
      "COALESCE(SUM(CASE WHEN status = 'completed' THEN total ELSE 0 END), 0) AS total_sum "
      'FROM sales $whereClause',
      variables: variables,
      readsFrom: {sales},
    ).get();

    if (rows.isEmpty) {
      return const DailySalesSummary(day: 'all', transactionCount: 0, totalRevenue: 0);
    }

    return DailySalesSummary(
      day: 'all',
      transactionCount: rows.first.read<int>('tx_count'),
      totalRevenue: rows.first.read<int>('total_sum'),
    );
  }
}

/// Penanda posisi untuk keyset pagination riwayat (transaksi terakhir yang sudah dimuat).
class SalesCursor {
  final DateTime createdAt;
  final int id;

  const SalesCursor({required this.createdAt, required this.id});

  factory SalesCursor.fromSale(Sale sale) =>
      SalesCursor(createdAt: sale.createdAt, id: sale.id);
}

/// Ringkasan satu hari (waktu lokal) pada riwayat transaksi.
class DailySalesSummary {
  /// Kunci hari lokal berformat `yyyy-MM-dd`.
  final String day;
  final int transactionCount;

  /// Omzet (Rupiah, integer) dari transaksi `completed`.
  final int totalRevenue;

  const DailySalesSummary({
    required this.day,
    required this.transactionCount,
    required this.totalRevenue,
  });
}

/// Kunci hari lokal `yyyy-MM-dd` untuk [moment] (dikonversi ke waktu lokal).
/// Harus selalu konsisten dengan pengelompokan `localtime` pada [SaleDao.getDailySummaries].
String localDayKey(DateTime moment) {
  final local = moment.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$month-$day';
}


