import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../app_database.dart';

/// Definisi Angka Laporan Keuangan POS Me (PROJECT_RULES.md Bagian 13):
/// - Omzet = jumlah sales.total status completed
/// - Pajak = sales.tax; Pendapatan bersih = omzet - pajak
/// - HPP = jumlah (qty x costPrice snapshot) dari sale_items
/// - Laba kotor = pendapatan bersih - HPP
class DashboardSummary {
  /// Total omzet dari transaksi completed (Rupiah int)
  final int omzet;

  /// Jumlah transaksi berstatus completed
  final int txCount;

  /// Total barang/item terjual dari transaksi completed
  final int itemsSold;

  /// Total pajak dari transaksi completed
  final int tax;

  /// Pendapatan bersih = omzet - pajak
  final int netRevenue;

  /// HPP (Harga Pokok Penjualan) = sum(qty * costPrice snapshot). Null bila tidak berizin report.view_profit.
  final int? cogs;

  /// Laba kotor = netRevenue - cogs. Null bila tidak berizin report.view_profit.
  final int? grossProfit;

  const DashboardSummary({
    required this.omzet,
    required this.txCount,
    required this.itemsSold,
    required this.tax,
    required this.netRevenue,
    this.cogs,
    this.grossProfit,
  });

  DashboardSummary copyWithProfitHidden() {
    return DashboardSummary(
      omzet: omzet,
      txCount: txCount,
      itemsSold: itemsSold,
      tax: tax,
      netRevenue: netRevenue,
      cogs: null,
      grossProfit: null,
    );
  }

  static const empty = DashboardSummary(
    omzet: 0,
    txCount: 0,
    itemsSold: 0,
    tax: 0,
    netRevenue: 0,
    cogs: 0,
    grossProfit: 0,
  );
}

/// Titik data harian untuk visualisasi grafik omzet 7 hari terakhir.
class DailyRevenuePoint {
  final String dateStr; // 'yyyy-MM-dd'
  final DateTime date;
  final int omzet;
  final int txCount;

  const DailyRevenuePoint({
    required this.dateStr,
    required this.date,
    required this.omzet,
    required this.txCount,
  });
}

/// Entitas produk dengan stok menipis (currentStock <= minStock).
class LowStockProductEntry {
  final Product product;
  final String? unitName;
  final String? categoryName;

  const LowStockProductEntry({
    required this.product,
    this.unitName,
    this.categoryName,
  });

  int get id => product.id;
  String get name => product.name;
  int get currentStock => product.currentStock;
  int get minStock => product.minStock;
  int get sellPrice => product.sellPrice;
  int get costPrice => product.costPrice;
}

/// Rekap penjualan harian untuk laporan dasar.
class DailySalesReportEntry {
  final String day; // 'yyyy-MM-dd'
  final DateTime date;
  final int txCount;
  final int omzet;

  const DailySalesReportEntry({
    required this.day,
    required this.date,
    required this.txCount,
    required this.omzet,
  });
}

/// Data item produk terlaris dalam rentang waktu tertentu.
class TopSellingProductEntry {
  final int productId;
  final String productName;
  final int totalQty;
  final int totalRevenue;
  final int? totalCost; // Null bila tidak berizin report.view_profit
  final int? grossProfit; // Null bila tidak berizin report.view_profit

  const TopSellingProductEntry({
    required this.productId,
    required this.productName,
    required this.totalQty,
    required this.totalRevenue,
    this.totalCost,
    this.grossProfit,
  });

  TopSellingProductEntry copyWithProfitHidden() {
    return TopSellingProductEntry(
      productId: productId,
      productName: productName,
      totalQty: totalQty,
      totalRevenue: totalRevenue,
      totalCost: null,
      grossProfit: null,
    );
  }
}

/// Data penjualan per kategori produk.
class CategorySalesEntry {
  final int? categoryId;
  final String categoryName;
  final int totalQty;
  final int totalRevenue;
  final double percentage; // Persentase omzet (0.0 - 100.0)

  const CategorySalesEntry({
    this.categoryId,
    required this.categoryName,
    required this.totalQty,
    required this.totalRevenue,
    this.percentage = 0.0,
  });

  CategorySalesEntry copyWithPercentage(double pct) {
    return CategorySalesEntry(
      categoryId: categoryId,
      categoryName: categoryName,
      totalQty: totalQty,
      totalRevenue: totalRevenue,
      percentage: pct,
    );
  }
}

/// Data penjualan per metode pembayaran.
class PaymentMethodSalesEntry {
  final String method;
  final int txCount;
  final int totalAmount;
  final double percentage; // Persentase omzet (0.0 - 100.0)

  const PaymentMethodSalesEntry({
    required this.method,
    required this.txCount,
    required this.totalAmount,
    this.percentage = 0.0,
  });

  PaymentMethodSalesEntry copyWithPercentage(double pct) {
    return PaymentMethodSalesEntry(
      method: method,
      txCount: txCount,
      totalAmount: totalAmount,
      percentage: pct,
    );
  }
}

/// Data penjualan per kasir (disembunyikan pada Mode Solo).
class CashierSalesEntry {
  final int cashierId;
  final String cashierName;
  final int txCount;
  final int totalRevenue;
  final int avgPerTx;

  const CashierSalesEntry({
    required this.cashierId,
    required this.cashierName,
    required this.txCount,
    required this.totalRevenue,
    required this.avgPerTx,
  });
}

/// Distribusi penjualan per jam (jam 00 s.d 23) untuk analisis jam ramai.
class HourlySalesEntry {
  final int hour; // 0..23
  final int txCount;
  final int totalRevenue;

  const HourlySalesEntry({
    required this.hour,
    required this.txCount,
    required this.totalRevenue,
  });

  String get hourLabel => '${hour.toString().padLeft(2, '0')}:00';
}

/// Ringkasan valuasi nilai modal stok dan potensi omzet.
class StockValuationSummary {
  final int totalProducts;
  final int totalStockQty;
  final int? totalCostValue; // Nilai modal stok (null jika tidak berizin)
  final int totalRetailValue; // Potensi omzet (stok * harga jual)
  final int? potentialProfit; // Potensi laba kotor (null jika tidak berizin)

  const StockValuationSummary({
    required this.totalProducts,
    required this.totalStockQty,
    this.totalCostValue,
    required this.totalRetailValue,
    this.potentialProfit,
  });

  static const empty = StockValuationSummary(
    totalProducts: 0,
    totalStockQty: 0,
    totalCostValue: 0,
    totalRetailValue: 0,
    potentialProfit: 0,
  );
}

/// Ringkasan stok menipis dan habis.
class LowAndOutStockSummary {
  final int outOfStockCount;
  final int lowStockCount;
  final List<LowStockProductEntry> outOfStockProducts;
  final List<LowStockProductEntry> lowStockProducts;

  const LowAndOutStockSummary({
    required this.outOfStockCount,
    required this.lowStockCount,
    required this.outOfStockProducts,
    required this.lowStockProducts,
  });

  static const empty = LowAndOutStockSummary(
    outOfStockCount: 0,
    lowStockCount: 0,
    outOfStockProducts: [],
    lowStockProducts: [],
  );
}

/// Ringkasan transaksi dibatalkan (void).
class VoidSummaryEntry {
  final int voidCount;
  final int totalVoidAmount;

  const VoidSummaryEntry({
    required this.voidCount,
    required this.totalVoidAmount,
  });

  static const empty = VoidSummaryEntry(
    voidCount: 0,
    totalVoidAmount: 0,
  );
}

class ReportDao extends DatabaseAccessor<AppDatabase> {
  ReportDao(super.db);

  $SalesTable get sales => db.sales;
  $SaleItemsTable get saleItems => db.saleItems;
  $ProductsTable get products => db.products;
  $UnitsTable get units => db.units;
  $CategoriesTable get categories => db.categories;
  $PaymentsTable get payments => db.payments;
  $UsersTable get users => db.users;

  /// Ringkasan angka agregat dalam rentang [from, to) waktu lokal.
  /// Memakai index sales.createdAt. Transaksi void TIDAK dihitung.
  Future<DashboardSummary> getSummaryForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    // 1. Agregat transaksi dari tabel sales
    final salesRow = await customSelect(
      'SELECT '
      'COUNT(*) AS tx_count, '
      'COALESCE(SUM(total), 0) AS total_omzet, '
      'COALESCE(SUM(tax), 0) AS total_tax '
      'FROM sales '
      "WHERE status = 'completed' "
      '  AND created_at >= ? '
      '  AND created_at < ?',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales},
    ).getSingleOrNull();

    final txCount = salesRow?.read<int>('tx_count') ?? 0;
    final omzet = salesRow?.read<int>('total_omzet') ?? 0;
    final tax = salesRow?.read<int>('total_tax') ?? 0;

    // 2. Agregat item dan HPP dari snapshot sale_items
    final itemsRow = await customSelect(
      'SELECT '
      'COALESCE(SUM(si.qty), 0) AS total_items, '
      'COALESCE(SUM(si.qty * si.cost_price), 0) AS total_cogs '
      'FROM sale_items si '
      'INNER JOIN sales s ON si.sale_id = s.id '
      "WHERE s.status = 'completed' "
      '  AND s.created_at >= ? '
      '  AND s.created_at < ?',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales, saleItems},
    ).getSingleOrNull();

    final itemsSold = itemsRow?.read<int>('total_items') ?? 0;
    final cogs = itemsRow?.read<int>('total_cogs') ?? 0;
    final netRevenue = omzet - tax;
    final grossProfit = netRevenue - cogs;

    return DashboardSummary(
      omzet: omzet,
      txCount: txCount,
      itemsSold: itemsSold,
      tax: tax,
      netRevenue: netRevenue,
      cogs: cogs,
      grossProfit: grossProfit,
    );
  }

  /// Data grafik omzet 7 hari terakhir (atau rentang [from, to)).
  /// Hasil query diagregasi per hari berdasar waktu lokal perangkat.
  Future<List<DailyRevenuePoint>> getRevenueChartDays({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      "SELECT strftime('%Y-%m-%d', created_at, 'unixepoch', 'localtime') AS day, "
      'COUNT(*) AS tx_count, '
      'COALESCE(SUM(total), 0) AS omzet '
      'FROM sales '
      "WHERE status = 'completed' "
      '  AND created_at >= ? '
      '  AND created_at < ? '
      'GROUP BY day '
      'ORDER BY day ASC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales},
    ).get();

    final map = <String, ({int omzet, int txCount})>{};
    for (final row in rows) {
      final day = row.read<String>('day');
      final omzet = row.read<int>('omzet');
      final txCount = row.read<int>('tx_count');
      map[day] = (omzet: omzet, txCount: txCount);
    }

    // Bangun deretan hari lengkap agar tidak ada gap tanggal
    final points = <DailyRevenuePoint>[];
    DateTime cursor = DateTime(from.year, from.month, from.day);
    final endLimit = DateTime(to.year, to.month, to.day);

    while (cursor.isBefore(endLimit)) {
      final dayStr = DateFormat('yyyy-MM-dd').format(cursor);
      final entry = map[dayStr];
      points.add(
        DailyRevenuePoint(
          dateStr: dayStr,
          date: cursor,
          omzet: entry?.omzet ?? 0,
          txCount: entry?.txCount ?? 0,
        ),
      );
      cursor = cursor.add(const Duration(days: 1));
    }

    return points;
  }

  /// Mengambil daftar produk aktif dengan stok menipis (currentStock <= minStock).
  Future<List<LowStockProductEntry>> getLowStockProducts({int limit = 5}) async {
    final query = select(products).join([
      leftOuterJoin(units, units.id.equalsExp(products.unitId)),
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ])
      ..where(products.isActive.equals(true) & products.currentStock.isSmallerOrEqual(products.minStock))
      ..orderBy([
        OrderingTerm(expression: products.currentStock, mode: OrderingMode.asc),
        OrderingTerm(expression: products.name, mode: OrderingMode.asc),
      ])
      ..limit(limit);

    final rows = await query.get();
    return rows.map((r) {
      return LowStockProductEntry(
        product: r.readTable(products),
        unitName: r.readTableOrNull(units)?.name,
        categoryName: r.readTableOrNull(categories)?.name,
      );
    }).toList();
  }

  /// Menghitung total banyaknya produk aktif dengan stok menipis.
  Future<int> countLowStockProducts() async {
    final countExp = products.id.count();
    final query = selectOnly(products)
      ..addColumns([countExp])
      ..where(products.isActive.equals(true) & products.currentStock.isSmallerOrEqual(products.minStock));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Rekap penjualan harian untuk rentang [from, to) (misal 30 hari terakhir).
  /// Diurutkan tanggal terbaru di atas (DESC).
  Future<List<DailySalesReportEntry>> getDailySalesReports({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      "SELECT strftime('%Y-%m-%d', created_at, 'unixepoch', 'localtime') AS day, "
      'COUNT(*) AS tx_count, '
      'COALESCE(SUM(total), 0) AS omzet '
      'FROM sales '
      "WHERE status = 'completed' "
      '  AND created_at >= ? '
      '  AND created_at < ? '
      'GROUP BY day '
      'ORDER BY day DESC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales},
    ).get();

    return rows.map((row) {
      final dayStr = row.read<String>('day');
      final date = DateTime.tryParse(dayStr) ?? DateTime.now();
      return DailySalesReportEntry(
        day: dayStr,
        date: date,
        txCount: row.read<int>('tx_count'),
        omzet: row.read<int>('omzet'),
      );
    }).toList();
  }

  /// Produk terlaris dalam rentang [from, to), diurutkan berdasarkan [sortBy] ('qty' atau 'revenue').
  Future<List<TopSellingProductEntry>> getTopSellingProducts({
    required DateTime from,
    required DateTime to,
    int limit = 20,
    String sortBy = 'qty',
  }) async {
    final orderClause = sortBy == 'revenue'
        ? 'total_revenue DESC, total_qty DESC'
        : 'total_qty DESC, total_revenue DESC';

    final rows = await customSelect(
      'SELECT '
      'si.product_id, '
      'si.product_name, '
      'COALESCE(SUM(si.qty), 0) AS total_qty, '
      'COALESCE(SUM(si.subtotal), 0) AS total_revenue, '
      'COALESCE(SUM(si.qty * si.cost_price), 0) AS total_cost '
      'FROM sale_items si '
      'INNER JOIN sales s ON si.sale_id = s.id '
      "WHERE s.status = 'completed' "
      '  AND s.created_at >= ? '
      '  AND s.created_at < ? '
      'GROUP BY si.product_id, si.product_name '
      'ORDER BY $orderClause '
      'LIMIT ?',
      variables: [
        Variable<DateTime>(from),
        Variable<DateTime>(to),
        Variable<int>(limit),
      ],
      readsFrom: {sales, saleItems},
    ).get();

    return rows.map((r) {
      final revenue = r.read<int>('total_revenue');
      final cost = r.read<int>('total_cost');
      return TopSellingProductEntry(
        productId: r.read<int>('product_id'),
        productName: r.read<String>('product_name'),
        totalQty: r.read<int>('total_qty'),
        totalRevenue: revenue,
        totalCost: cost,
        grossProfit: revenue - cost,
      );
    }).toList();
  }

  /// Penjualan per kategori dalam rentang [from, to).
  Future<List<CategorySalesEntry>> getCategorySales({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      'SELECT '
      'p.category_id, '
      "COALESCE(c.name, 'Tanpa Kategori') AS category_name, "
      'COALESCE(SUM(si.qty), 0) AS total_qty, '
      'COALESCE(SUM(si.subtotal), 0) AS total_revenue '
      'FROM sale_items si '
      'INNER JOIN sales s ON si.sale_id = s.id '
      'LEFT JOIN products p ON si.product_id = p.id '
      'LEFT JOIN categories c ON p.category_id = c.id '
      "WHERE s.status = 'completed' "
      '  AND s.created_at >= ? '
      '  AND s.created_at < ? '
      'GROUP BY p.category_id, category_name '
      'ORDER BY total_revenue DESC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales, saleItems, products, categories},
    ).get();

    final list = rows.map((r) {
      return CategorySalesEntry(
        categoryId: r.read<int?>('category_id'),
        categoryName: r.read<String>('category_name'),
        totalQty: r.read<int>('total_qty'),
        totalRevenue: r.read<int>('total_revenue'),
      );
    }).toList();

    final totalCatRevenue = list.fold<int>(0, (sum, e) => sum + e.totalRevenue);
    return list.map((e) {
      final pct = totalCatRevenue > 0 ? (e.totalRevenue / totalCatRevenue * 100) : 0.0;
      return e.copyWithPercentage(pct);
    }).toList();
  }

  /// Penjualan per metode pembayaran dalam rentang [from, to).
  Future<List<PaymentMethodSalesEntry>> getPaymentMethodSales({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      'SELECT '
      'p.method, '
      'COUNT(p.id) AS tx_count, '
      'COALESCE(SUM(p.amount), 0) AS total_amount '
      'FROM payments p '
      'INNER JOIN sales s ON p.sale_id = s.id '
      "WHERE s.status = 'completed' "
      '  AND s.created_at >= ? '
      '  AND s.created_at < ? '
      'GROUP BY p.method '
      'ORDER BY total_amount DESC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales, payments},
    ).get();

    final list = rows.map((r) {
      return PaymentMethodSalesEntry(
        method: r.read<String>('method'),
        txCount: r.read<int>('tx_count'),
        totalAmount: r.read<int>('total_amount'),
      );
    }).toList();

    final totalAll = list.fold<int>(0, (sum, e) => sum + e.totalAmount);
    return list.map((e) {
      final pct = totalAll > 0 ? (e.totalAmount / totalAll * 100) : 0.0;
      return e.copyWithPercentage(pct);
    }).toList();
  }

  /// Penjualan per kasir dalam rentang [from, to) (disembunyikan di Mode Solo).
  Future<List<CashierSalesEntry>> getCashierSales({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      'SELECT '
      's.cashier_id, '
      "COALESCE(u.display_name, 'Kasir ' || s.cashier_id) AS cashier_name, "
      'COUNT(*) AS tx_count, '
      'COALESCE(SUM(s.total), 0) AS total_revenue '
      'FROM sales s '
      'LEFT JOIN users u ON s.cashier_id = u.id '
      "WHERE s.status = 'completed' "
      '  AND s.created_at >= ? '
      '  AND s.created_at < ? '
      'GROUP BY s.cashier_id, cashier_name '
      'ORDER BY total_revenue DESC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales, users},
    ).get();

    return rows.map((r) {
      final txCount = r.read<int>('tx_count');
      final totalRevenue = r.read<int>('total_revenue');
      final avg = txCount > 0 ? (totalRevenue / txCount).round() : 0;
      return CashierSalesEntry(
        cashierId: r.read<int>('cashier_id'),
        cashierName: r.read<String>('cashier_name'),
        txCount: txCount,
        totalRevenue: totalRevenue,
        avgPerTx: avg,
      );
    }).toList();
  }

  /// Distribusi penjualan per jam dalam rentang [from, to) (24 jam 00..23).
  Future<List<HourlySalesEntry>> getHourlySales({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      "SELECT CAST(strftime('%H', created_at, 'unixepoch', 'localtime') AS INTEGER) AS hour, "
      'COUNT(*) AS tx_count, '
      'COALESCE(SUM(total), 0) AS total_revenue '
      'FROM sales '
      "WHERE status = 'completed' "
      '  AND created_at >= ? '
      '  AND created_at < ? '
      'GROUP BY hour '
      'ORDER BY hour ASC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales},
    ).get();

    final map = <int, ({int txCount, int totalRevenue})>{};
    for (final r in rows) {
      final hour = r.read<int>('hour');
      map[hour] = (
        txCount: r.read<int>('tx_count'),
        totalRevenue: r.read<int>('total_revenue'),
      );
    }

    return List.generate(24, (hour) {
      final entry = map[hour];
      return HourlySalesEntry(
        hour: hour,
        txCount: entry?.txCount ?? 0,
        totalRevenue: entry?.totalRevenue ?? 0,
      );
    });
  }

  /// Valuasi nilai modal stok dan potensi omzet untuk seluruh produk aktif.
  Future<StockValuationSummary> getStockValuation() async {
    final row = await customSelect(
      'SELECT '
      'COUNT(*) AS total_products, '
      'COALESCE(SUM(CASE WHEN current_stock > 0 THEN current_stock ELSE 0 END), 0) AS total_stock_qty, '
      'COALESCE(SUM(CASE WHEN current_stock > 0 THEN current_stock * cost_price ELSE 0 END), 0) AS total_cost_value, '
      'COALESCE(SUM(CASE WHEN current_stock > 0 THEN current_stock * sell_price ELSE 0 END), 0) AS total_retail_value '
      'FROM products '
      'WHERE is_active = 1',
      readsFrom: {products},
    ).getSingleOrNull();

    final totalProducts = row?.read<int>('total_products') ?? 0;
    final totalStockQty = row?.read<int>('total_stock_qty') ?? 0;
    final totalCostValue = row?.read<int>('total_cost_value') ?? 0;
    final totalRetailValue = row?.read<int>('total_retail_value') ?? 0;

    return StockValuationSummary(
      totalProducts: totalProducts,
      totalStockQty: totalStockQty,
      totalCostValue: totalCostValue,
      totalRetailValue: totalRetailValue,
      potentialProfit: totalRetailValue - totalCostValue,
    );
  }

  /// Ringkasan produk dengan stok habis (stok <= 0) dan stok menipis (0 < stok <= minStock).
  Future<LowAndOutStockSummary> getLowAndOutStockSummary({int limit = 50}) async {
    final outRows = await (select(products).join([
      leftOuterJoin(units, units.id.equalsExp(products.unitId)),
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ])
      ..where(products.isActive.equals(true) & products.currentStock.isSmallerOrEqual(const Constant(0)))
      ..orderBy([
        OrderingTerm(expression: products.currentStock, mode: OrderingMode.asc),
        OrderingTerm(expression: products.name, mode: OrderingMode.asc),
      ])
      ..limit(limit))
      .get();

    final outCountExp = products.id.count();
    final outCountRow = await (selectOnly(products)
      ..addColumns([outCountExp])
      ..where(products.isActive.equals(true) & products.currentStock.isSmallerOrEqual(const Constant(0))))
      .getSingle();
    final outCount = outCountRow.read(outCountExp) ?? 0;

    final lowRows = await (select(products).join([
      leftOuterJoin(units, units.id.equalsExp(products.unitId)),
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ])
      ..where(products.isActive.equals(true) &
          products.currentStock.isBiggerThan(const Constant(0)) &
          products.currentStock.isSmallerOrEqual(products.minStock))
      ..orderBy([
        OrderingTerm(expression: products.currentStock, mode: OrderingMode.asc),
        OrderingTerm(expression: products.name, mode: OrderingMode.asc),
      ])
      ..limit(limit))
      .get();

    final lowCountExp = products.id.count();
    final lowCountRow = await (selectOnly(products)
      ..addColumns([lowCountExp])
      ..where(products.isActive.equals(true) &
          products.currentStock.isBiggerThan(const Constant(0)) &
          products.currentStock.isSmallerOrEqual(products.minStock)))
      .getSingle();
    final lowCount = lowCountRow.read(lowCountExp) ?? 0;

    return LowAndOutStockSummary(
      outOfStockCount: outCount,
      lowStockCount: lowCount,
      outOfStockProducts: outRows.map((r) => LowStockProductEntry(
        product: r.readTable(products),
        unitName: r.readTableOrNull(units)?.name,
        categoryName: r.readTableOrNull(categories)?.name,
      )).toList(),
      lowStockProducts: lowRows.map((r) => LowStockProductEntry(
        product: r.readTable(products),
        unitName: r.readTableOrNull(units)?.name,
        categoryName: r.readTableOrNull(categories)?.name,
      )).toList(),
    );
  }

  /// Ringkasan transaksi void dalam rentang [from, to).
  Future<VoidSummaryEntry> getVoidSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final row = await customSelect(
      'SELECT '
      'COUNT(*) AS void_count, '
      'COALESCE(SUM(total), 0) AS total_void_amount '
      'FROM sales '
      "WHERE status = 'void' "
      '  AND created_at >= ? '
      '  AND created_at < ?',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {sales},
    ).getSingleOrNull();

    return VoidSummaryEntry(
      voidCount: row?.read<int>('void_count') ?? 0,
      totalVoidAmount: row?.read<int>('total_void_amount') ?? 0,
    );
  }
}

