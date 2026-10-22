import 'package:get/get.dart';

import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../local/daos/customer_dao.dart';
import '../local/daos/expense_dao.dart';
import '../local/daos/report_dao.dart';

/// Data agregat dashboard utama.
class DashboardData {
  /// Omzet hari ini (Penjualan Bersih setelah retur, Rupiah integer, status completed)
  final int todayOmzet;

  /// Omzet kotor hari ini sebelum retur
  final int todayGrossOmzet;

  /// Total nominal retur hari ini
  final int todayReturns;

  /// Jumlah transaksi retur hari ini
  final int todayReturnCount;

  /// Jumlah transaksi hari ini
  final int todayTxCount;

  /// Total barang/item terjual hari ini
  final int todayItemsSold;

  /// Laba kotor hari ini (null jika user tidak memiliki izin report.view_profit)
  final int? todayProfit;

  /// Laba bersih hari ini = laba kotor - pengeluaran (null jika user tidak memiliki izin report.view_profit)
  final int? todayNetProfit;

  /// Total pengeluaran hari ini (null jika user tidak memiliki akses pengeluaran)
  final int? todayExpenses;

  /// HPP hari ini (null jika user tidak memiliki izin report.view_profit)
  final int? todayCogs;

  /// Pajak hari ini (null jika user tidak memiliki izin report.view_profit)
  final int? todayTax;

  /// Total piutang kasbon saat ini (null jika user tidak memiliki izin customer.view)
  final int? todayReceivables;

  /// Total diskon hari ini
  final int todayDiscount;

  /// Data deret omzet 7 hari terakhir untuk grafik
  final List<DailyRevenuePoint> revenueChart;

  /// Daftar produk dengan stok menipis (maksimal 5)
  final List<LowStockProductEntry> lowStockProducts;

  /// Total jumlah produk aktif yang stoknya menipis
  final int totalLowStockCount;

  const DashboardData({
    required this.todayOmzet,
    this.todayGrossOmzet = 0,
    this.todayReturns = 0,
    this.todayReturnCount = 0,
    required this.todayTxCount,
    required this.todayItemsSold,
    this.todayProfit,
    this.todayNetProfit,
    this.todayExpenses,
    this.todayCogs,
    this.todayTax,
    this.todayReceivables,
    this.todayDiscount = 0,
    required this.revenueChart,
    required this.lowStockProducts,
    required this.totalLowStockCount,
  });
}

/// Data laporan lengkap komprehensif (Semi-Premium ke atas).
/// Model ini juga berfungsi sebagai payload siap pakai untuk ekspor file (Prompt 14).
class FullReportData {
  final DateTime from;
  final DateTime to;
  final DashboardSummary summary;
  final int avgTxValue;
  final List<TopSellingProductEntry> topProducts;
  final List<CategorySalesEntry> categorySales;
  final List<PaymentMethodSalesEntry> paymentMethodSales;
  final List<CashierSalesEntry>? cashierSales; // null bila Mode Solo
  final List<HourlySalesEntry> hourlySales;
  final StockValuationSummary? stockValuation;
  final LowAndOutStockSummary stockAlerts;
  final VoidSummaryEntry voidSummary;
  final List<ExpenseCategoryAggregate> expenseCategoryBreakdown;
  final List<CustomerAgingItem> agingReport;
  final bool isProfitVisible;

  const FullReportData({
    required this.from,
    required this.to,
    required this.summary,
    required this.avgTxValue,
    required this.topProducts,
    required this.categorySales,
    required this.paymentMethodSales,
    this.cashierSales,
    required this.hourlySales,
    this.stockValuation,
    required this.stockAlerts,
    required this.voidSummary,
    this.expenseCategoryBreakdown = const [],
    this.agingReport = const [],
    required this.isProfitVisible,
  });
}

/// Repository untuk Laporan dan Dashboard POS Me.
///
/// Definisi angka konsisten (PROJECT_RULES.md Bagian 13):
/// - Omzet = jumlah sales.total status completed
/// - Pajak = sales.tax; Pendapatan bersih = omzet - pajak
/// - HPP = jumlah (qty x costPrice snapshot) dari sale_items
/// - Laba kotor = pendapatan bersih - HPP
class ReportRepository {
  final ReportDao _reportDao;
  final PermissionService? _permissionService;
  final FeatureGate? _featureGate;

  ReportRepository(
    this._reportDao, {
    PermissionService? permissionService,
    FeatureGate? featureGate,
  })  : _permissionService = permissionService,
        _featureGate = featureGate;

  bool _isFeatureEnabled(Feature feature) {
    if (_featureGate != null) {
      return _featureGate.isEnabled(feature);
    }
    if (Get.isRegistered<FeatureGate>()) {
      return FeatureGate.to.isEnabled(feature);
    }
    return false;
  }

  bool _hasPermission(String key) {
    if (_permissionService != null) {
      return _permissionService.can(key);
    }
    if (Get.isRegistered<PermissionService>()) {
      return PermissionService.to.can(key);
    }
    return true;
  }

  /// Memuat data ringkasan dashboard untuk hari ini (waktu lokal perangkat).
  ///
  /// Laba kotor dan HPP hanya disertakan bila user memiliki hak akses `report.view_profit`.
  /// Jika tidak berizin, nilai laba kotor bernilai `null` untuk mencegah kebocoran angka sensitif.
  Future<DashboardData> getDashboardData({DateTime? customNow}) async {
    final now = customNow ?? DateTime.now();
    // Batas hari berdasarkan waktu lokal perangkat
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    // 7 hari terakhir: dari 6 hari lalu sampai akhir hari ini
    final chartStart = DateTime(now.year, now.month, now.day - 6, 0, 0, 0);
    final chartEnd = endOfDay;

    final summary = await _reportDao.getSummaryForRange(from: startOfDay, to: endOfDay);
    final chartPoints = await _reportDao.getRevenueChartDays(from: chartStart, to: chartEnd);
    final lowStock = await _reportDao.getLowStockProducts(limit: 5);
    final lowStockCount = await _reportDao.countLowStockProducts();

    final canViewProfit = _hasPermission(PermissionKeys.reportViewProfit);
    final canViewExpenses = _isFeatureEnabled(Feature.expenses) &&
        _hasPermission(PermissionKeys.expenseView);
    final canViewReceivables = _isFeatureEnabled(Feature.customerCredit) &&
        _hasPermission(PermissionKeys.customerView);

    return DashboardData(
      todayOmzet: summary.netSales,
      todayGrossOmzet: summary.grossOmzet,
      todayReturns: summary.totalReturns,
      todayReturnCount: summary.returnCount,
      todayTxCount: summary.txCount,
      todayItemsSold: summary.itemsSold,
      todayProfit: canViewProfit ? summary.grossProfit : null,
      todayNetProfit: canViewProfit ? summary.netProfit : null,
      todayExpenses: canViewExpenses ? summary.totalExpenses : null,
      todayCogs: canViewProfit ? summary.cogs : null,
      todayTax: canViewProfit ? summary.netTax : null,
      todayReceivables: canViewReceivables ? summary.totalReceivables : null,
      todayDiscount: summary.totalDiscount,
      revenueChart: chartPoints,
      lowStockProducts: lowStock,
      totalLowStockCount: lowStockCount,
    );
  }

  /// Rekap penjualan harian untuk laporan dasar (default 30 hari terakhir).
  ///
  /// Wajib memiliki hak akses `report.view_basic`.
  Future<List<DailySalesReportEntry>> getDailySalesReport({
    DateTime? customNow,
    int days = 30,
  }) async {
    if (!_hasPermission(PermissionKeys.reportViewBasic)) {
      throw const AppException(
        'Akses ditolak: Anda tidak memiliki izin melihat laporan dasar (report.view_basic).',
      );
    }

    final now = customNow ?? DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1), 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    return _reportDao.getDailySalesReports(from: start, to: end);
  }

  /// Mengambil data laporan lengkap komprehensif dalam rentang [from, to).
  ///
  /// Pengecekan keamanan & lisensi:
  /// 1. Lisensi: Wajib memiliki fitur `Feature.fullReports` (Semi-Premium ke atas).
  ///    Jika belum, melempar AppException(..., code: 'FEATURE_LOCKED').
  /// 2. Izin dasar: Wajib memiliki izin `report.view_basic`.
  ///    Jika belum, melempar AppException(..., code: 'FORBIDDEN').
  /// 3. Laba & HPP: Hanya disertakan jika memiliki izin `report.view_profit`.
  ///    Jika tidak memiliki izin tersebut, nilai HPP, laba kotor, dan modal stok
  ///    disensor menjadi `null` untuk melindungi data sensitif pemilik toko.
  /// 4. Mode Solo: Jika toko berada pada mode Solo, `cashierSales` disembunyikan (bernilai `null`).
  Future<FullReportData> getFullReport({
    required DateTime from,
    required DateTime to,
    String topSellingSortBy = 'qty',
    bool? isSoloMode,
  }) async {
    // 1. Feature Gate (Semi Premium ke atas)
    if (!_isFeatureEnabled(Feature.fullReports)) {
      throw const AppException(
        'Fitur Laporan Lengkap memerlukan lisensi Semi-Premium ke atas.',
        code: 'FEATURE_LOCKED',
      );
    }

    // 2. Izin dasar report.view_basic
    if (!_hasPermission(PermissionKeys.reportViewBasic)) {
      throw const AppException(
        'Akses ditolak: Anda tidak memiliki izin melihat laporan dasar (report.view_basic).',
        code: 'FORBIDDEN',
      );
    }

    final canViewProfit = _hasPermission(PermissionKeys.reportViewProfit);

    // Deteksi mode solo (sembunyikan per kasir)
    final solo = isSoloMode ??
        (Get.isRegistered<AuthService>() ? AuthService.to.isSoloMode : false);

    // Ambil data agregat dari DAO
    final summaryRaw = await _reportDao.getSummaryForRange(from: from, to: to);
    final topProductsRaw = await _reportDao.getTopSellingProducts(
      from: from,
      to: to,
      limit: 20,
      sortBy: topSellingSortBy,
    );
    final categorySales = await _reportDao.getCategorySales(from: from, to: to);
    final paymentMethodSales = await _reportDao.getPaymentMethodSales(from: from, to: to);
    final cashierSales = solo ? null : await _reportDao.getCashierSales(from: from, to: to);
    final hourlySales = await _reportDao.getHourlySales(from: from, to: to);
    final stockValuationRaw = await _reportDao.getStockValuation();
    final stockAlerts = await _reportDao.getLowAndOutStockSummary(limit: 50);
    final voidSummary = await _reportDao.getVoidSummary(from: from, to: to);
    final expenseBreakdown = await _reportDao.getExpenseCategoryBreakdown(
      from: from,
      to: to,
    );
    final agingReport = await _reportDao.attachedDatabase.customerDao.getAgingReport();

    // Sensor angka laba & HPP jika tidak punya izin report.view_profit
    final summary = canViewProfit ? summaryRaw : summaryRaw.copyWithProfitHidden();
    final topProducts = canViewProfit
        ? topProductsRaw
        : topProductsRaw.map((p) => p.copyWithProfitHidden()).toList();
    final stockValuation = canViewProfit
        ? stockValuationRaw
        : StockValuationSummary(
            totalProducts: stockValuationRaw.totalProducts,
            totalStockQty: stockValuationRaw.totalStockQty,
            totalCostValue: null,
            totalRetailValue: stockValuationRaw.totalRetailValue,
            potentialProfit: null,
          );

    final avgTx = summary.txCount > 0 ? (summary.omzet / summary.txCount).round() : 0;

    return FullReportData(
      from: from,
      to: to,
      summary: summary,
      avgTxValue: avgTx,
      topProducts: topProducts,
      categorySales: categorySales,
      paymentMethodSales: paymentMethodSales,
      cashierSales: cashierSales,
      hourlySales: hourlySales,
      stockValuation: stockValuation,
      stockAlerts: stockAlerts,
      voidSummary: voidSummary,
      expenseCategoryBreakdown: expenseBreakdown,
      agingReport: agingReport,
      isProfitVisible: canViewProfit,
    );
  }
}
