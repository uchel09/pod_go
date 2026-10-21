import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/intl.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/audit_dao.dart';
import '../local/daos/opname_dao.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/purchase_dao.dart';
import '../local/daos/report_dao.dart';
import '../local/daos/sale_dao.dart';
import '../local/daos/stock_dao.dart';
import '../models/export_models.dart';
import 'report_repository.dart';

/// Repository untuk mengelola proses ekspor data sistem POS Me
/// ke format CSV (UTF-8 dengan BOM) dan Excel Spreadsheet (XLSX).
///
/// Mengikuti aturan ketat:
/// - Gating dua lapis: Lisensi Semi-Premium (`Feature.importExport`) & Hak Akses (`report.export`)
/// - Sensor kolom sensitif: Harga beli (`product.view_cost`) & Laba kotor/HPP (`report.view_profit`)
/// - Perlindungan log audit: Hak akses khusus (`audit.view`)
/// - Jejak audit otomatis setiap kali ekspor dijalankan (`AuditActions.exportRun`)
class ExportRepository {
  final AppDatabase _db;
  final SaleDao _saleDao;
  final StockDao _stockDao;
  final OpnameDao _opnameDao;
  final PurchaseDao _purchaseDao;
  final AuditDao _auditDao;

  ExportRepository({
    required AppDatabase db,
    ProductDao? productDao,
    required SaleDao saleDao,
    required StockDao stockDao,
    required OpnameDao opnameDao,
    required PurchaseDao purchaseDao,
    required AuditDao auditDao,
    ReportDao? reportDao,
  })  : _db = db,
        _saleDao = saleDao,
        _stockDao = stockDao,
        _opnameDao = opnameDao,
        _purchaseDao = purchaseDao,
        _auditDao = auditDao;

  // =========================================================================
  // GATING & VERIFIKASI HAK AKSES
  // =========================================================================

  void _assertExportAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        throw const AppException(
          'Fitur Ekspor Data memerlukan lisensi Semi Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.reportExport)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk mengekspor data (report.export).',
          code: 'FORBIDDEN',
        );
      }
    }
  }

  bool get _canViewCost {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.productViewCost);
  }

  bool get _canViewProfit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportViewProfit);
  }

  // =========================================================================
  // LOG JEJAK AUDIT
  // =========================================================================

  Future<void> _recordAudit({
    required String type,
    required String format,
    required int rowCount,
    String? range,
  }) async {
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.exportRun,
        entity: type,
        detail: {
          'type': type,
          'format': format,
          'rowCount': rowCount,
          if (range != null && range.isNotEmpty) 'range': range,
        },
      );
    }
  }

  // =========================================================================
  // FORMATTING & FILE ENCODING
  // =========================================================================

  /// Mengonversi tabel baris menjadi byte CSV dengan UTF-8 BOM (`[0xEF, 0xBB, 0xBF]`)
  /// agar karakter terbaca rapi dan kompatibel di Microsoft Excel Windows.
  List<int> _encodeCsvWithBom(List<List<dynamic>> rows) {
    final csvContent = csv.encode(rows);
    final utf8Bytes = utf8.encode(csvContent);
    return <int>[0xEF, 0xBB, 0xBF, ...utf8Bytes];
  }

  /// Mengonversi tabel baris menjadi byte berkas Excel (.xlsx) dengan 1 lembar (sheet).
  List<int> _encodeXlsx(String sheetTitle, List<String> headers, List<List<dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheetName = sheetTitle.length > 31 ? sheetTitle.substring(0, 31) : sheetTitle;
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    if (sheetName != 'Sheet1' && excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Tulis Header
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Tulis Baris Data
    for (final row in rows) {
      final cells = row.map<CellValue>((v) {
        if (v == null) return TextCellValue('');
        if (v is int) return IntCellValue(v);
        if (v is double) return DoubleCellValue(v);
        if (v is bool) return TextCellValue(v ? 'Ya' : 'Tidak');
        return TextCellValue(v.toString());
      }).toList();
      sheet.appendRow(cells);
    }

    return excel.save() ?? <int>[];
  }

  String _generateFileName(ExportType type, ExportFormat format) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${type.filePrefix}_$timestamp.${format.extension}';
  }

  // =========================================================================
  // 1. EKSPOR KATALOG PRODUK
  // =========================================================================

  Future<ExportResult> exportProducts({required ExportFormat format}) async {
    _assertExportAccess();

    final canViewCost = _canViewCost;

    // Ambil produk beserta nama kategori dan satuan
    final query = _db.select(_db.products).join([
      drift.leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.products.categoryId)),
      drift.leftOuterJoin(_db.units, _db.units.id.equalsExp(_db.products.unitId)),
    ])..orderBy([drift.OrderingTerm.asc(_db.products.name)]);

    final rowsResult = await query.get();

    final headers = <String>[
      'Kode Internal',
      'Nama Produk',
      'Barcode',
      'SKU',
      'Kategori',
      'Satuan',
      'Stok Saat Ini',
      'Stok Minimum',
      'Harga Jual',
      if (canViewCost) 'Harga Beli',
      'Status',
    ];

    final rows = <List<dynamic>>[];
    for (final row in rowsResult) {
      final p = row.readTable(_db.products);
      final c = row.readTableOrNull(_db.categories);
      final u = row.readTableOrNull(_db.units);

      rows.add([
        p.internalCode,
        p.name,
        p.barcode ?? '',
        p.sku ?? '',
        c?.name ?? '',
        u?.name ?? '',
        p.currentStock,
        p.minStock,
        p.sellPrice,
        if (canViewCost) p.costPrice,
        p.isActive ? 'Aktif' : 'Nonaktif',
      ]);
    }

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Katalog Produk', headers, rows);

    final fileName = _generateFileName(ExportType.product, format);

    await _recordAudit(
      type: ExportType.product.name,
      format: format.name,
      rowCount: rows.length,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.product,
    );
  }

  // =========================================================================
  // 2. EKSPOR PENJUALAN (HEADER + DETAIL ITEM)
  // =========================================================================

  Future<ExportResult> exportSales({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    _assertExportAccess();

    final canViewProfit = _canViewProfit;

    final sales = await _saleDao.getSalesPage(
      limit: 1000000,
      startDate: from,
      endDate: to,
      status: status,
    );

    final saleIds = sales.map((s) => s.id).toList();

    // Batch load metode pembayaran dan nama kasir
    final payments = await _saleDao.getPaymentsBySaleIds(saleIds);
    final paymentsMap = <int, List<String>>{};
    for (final p in payments) {
      paymentsMap.putIfAbsent(p.saleId, () => []).add(p.method);
    }

    final cashierIds = sales.map((s) => s.cashierId).toSet();
    final cashierMap = await _saleDao.getUserDisplayNames(cashierIds);

    // Batch load item penjualan
    final allItems = saleIds.isEmpty
        ? <SaleItem>[]
        : await (_db.select(_db.saleItems)
              ..where((t) => t.saleId.isIn(saleIds))
              ..orderBy([(t) => drift.OrderingTerm.asc(t.id)]))
            .get();

    final itemsMap = <int, List<SaleItem>>{};
    for (final it in allItems) {
      itemsMap.putIfAbsent(it.saleId, () => []).add(it);
    }

    final headers = <String>[
      'No Transaksi',
      'Tanggal Transaksi',
      'Status',
      'Kasir',
      'Metode Pembayaran',
      'Nama Produk',
      'Jumlah (Qty)',
      'Harga Satuan',
      'Subtotal Item',
      if (canViewProfit) ...['Harga Modal Snapshot', 'Laba Kotor Item'],
      'Diskon Transaksi',
      'Pajak Transaksi',
      'Total Transaksi',
      'Alasan Void',
    ];

    final rows = <List<dynamic>>[];
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    for (final s in sales) {
      final items = itemsMap[s.id] ?? [];
      final paymentText = paymentsMap[s.id]?.join(', ') ?? 'Tunai';
      final cashierName = cashierMap[s.cashierId] ?? 'Kasir #${s.cashierId}';
      final formattedDate = dateFmt.format(s.createdAt.toLocal());

      if (items.isEmpty) {
        rows.add([
          s.invoiceNo,
          formattedDate,
          s.status,
          cashierName,
          paymentText,
          '-',
          0,
          0,
          0,
          if (canViewProfit) ...[0, 0],
          s.discount,
          s.tax,
          s.total,
          s.voidReason ?? '',
        ]);
      } else {
        for (final item in items) {
          final itemProfit = item.subtotal - (item.qty * item.costPrice);
          rows.add([
            s.invoiceNo,
            formattedDate,
            s.status,
            cashierName,
            paymentText,
            item.productName,
            item.qty,
            item.price,
            item.subtotal,
            if (canViewProfit) ...[item.costPrice, itemProfit],
            s.discount,
            s.tax,
            s.total,
            s.voidReason ?? '',
          ]);
        }
      }
    }

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Rincian Penjualan', headers, rows);

    final fileName = _generateFileName(ExportType.sales, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.sales.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.sales,
    );
  }

  // =========================================================================
  // 3. EKSPOR MUTASI STOK (KARTU STOK)
  // =========================================================================

  Future<ExportResult> exportStockMovements({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    int? productId,
    String? type,
  }) async {
    _assertExportAccess();

    final entries = await _stockDao.getStockCardPage(
      limit: 1000000,
      startDate: from,
      endDate: to,
      productId: productId,
      type: type,
    );

    final headers = <String>[
      'Waktu',
      'Nama Produk',
      'Tipe Mutasi',
      'Perubahan Stok',
      'Sisa Stok',
      'Tabel Referensi',
      'ID Referensi',
      'Catatan',
      'Dibuat Oleh',
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = entries.map((e) {
      return [
        dateFmt.format(e.createdAt.toLocal()),
        e.productName,
        e.type,
        e.qtyChange,
        e.stockAfter,
        e.refTable ?? '',
        e.refId?.toString() ?? '',
        e.note ?? '',
        e.userName,
      ];
    }).toList();

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Mutasi Stok', headers, rows);

    final fileName = _generateFileName(ExportType.stockCard, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.stockCard.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.stockCard,
    );
  }

  // =========================================================================
  // 4. EKSPOR HASIL OPNAME
  // =========================================================================

  Future<ExportResult> exportStockOpname({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    int? opnameId,
  }) async {
    _assertExportAccess();

    final canViewCost = _canViewCost;

    List<OpnameDetailEntry> opnameDetails = [];

    if (opnameId != null) {
      final detail = await _opnameDao.getOpnameDetail(opnameId);
      if (detail != null) {
        opnameDetails.add(detail);
      }
    } else {
      final summaries = await _opnameDao.getOpnamesPaged(
        limit: 1000,
        startDate: from,
        endDate: to,
      );
      for (final s in summaries) {
        final d = await _opnameDao.getOpnameDetail(s.opname.id);
        if (d != null) {
          opnameDetails.add(d);
        }
      }
    }

    final headers = <String>[
      'Kode Opname',
      'Tanggal',
      'Status',
      'Dibuat Oleh',
      'Catatan Sesi',
      'Nama Produk',
      'Stok Sistem',
      'Stok Fisik',
      'Selisih',
      if (canViewCost) ...['Harga Beli Satuan', 'Nilai Selisih'],
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<dynamic>>[];

    for (final op in opnameDetails) {
      final dateStr = dateFmt.format(op.opname.date.toLocal());
      if (op.items.isEmpty) {
        rows.add([
          op.code,
          dateStr,
          op.status,
          op.creatorName ?? 'Admin',
          op.opname.note ?? '',
          '-',
          0,
          0,
          0,
          if (canViewCost) ...[0, 0],
        ]);
      } else {
        for (final it in op.items) {
          rows.add([
            op.code,
            dateStr,
            op.status,
            op.creatorName ?? 'Admin',
            op.opname.note ?? '',
            it.product.name,
            it.systemQty,
            it.isCounted ? it.countedQty : '-',
            it.difference,
            if (canViewCost) ...[it.product.costPrice, it.differenceValue],
          ]);
        }
      }
    }

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Hasil Opname', headers, rows);

    final fileName = _generateFileName(ExportType.stockOpname, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.stockOpname.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.stockOpname,
    );
  }

  // =========================================================================
  // 5. EKSPOR PEMBELIAN / PENERIMAAN BARANG
  // =========================================================================

  Future<ExportResult> exportPurchases({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    int? supplierId,
  }) async {
    _assertExportAccess();

    final canViewCost = _canViewCost || _canViewProfit;

    final purchases = await _purchaseDao.getPurchasesPage(
      limit: 1000000,
      startDate: from,
      endDate: to,
      supplierId: supplierId,
    );

    final headers = <String>[
      'No Referensi',
      'Tanggal',
      'Pemasok',
      'Status',
      'Nama Produk',
      'Jumlah (Qty)',
      if (canViewCost) ...['Harga Beli Satuan', 'Subtotal Item'],
      'Total Pembelian',
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<dynamic>>[];

    for (final p in purchases) {
      final items = await _purchaseDao.getItemsByPurchaseId(p.purchase.id);
      final dateStr = dateFmt.format(p.purchase.date.toLocal());

      if (items.isEmpty) {
        rows.add([
          p.purchase.refNo,
          dateStr,
          p.supplierName,
          p.purchase.status,
          '-',
          0,
          if (canViewCost) ...[0, 0],
          p.purchase.total,
        ]);
      } else {
        // Ambil nama produk untuk items
        final productIds = items.map((i) => i.productId).toList();
        final prods = await (_db.select(_db.products)..where((t) => t.id.isIn(productIds))).get();
        final prodMap = {for (final pr in prods) pr.id: pr.name};

        for (final item in items) {
          final prodName = prodMap[item.productId] ?? 'Produk #${item.productId}';
          final subtotal = item.qty * item.costPrice;
          rows.add([
            p.purchase.refNo,
            dateStr,
            p.supplierName,
            p.purchase.status,
            prodName,
            item.qty,
            if (canViewCost) ...[item.costPrice, subtotal],
            p.purchase.total,
          ]);
        }
      }
    }

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Data Pembelian', headers, rows);

    final fileName = _generateFileName(ExportType.purchases, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.purchases.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.purchases,
    );
  }

  // =========================================================================
  // 6. EKSPOR LAPORAN LENGKAP (FULL REPORT DATA)
  // =========================================================================

  Future<ExportResult> exportFullReport(
    FullReportData data, {
    required ExportFormat format,
  }) async {
    _assertExportAccess();

    final bytes = format == ExportFormat.csv
        ? _encodeFullReportCsv(data)
        : _encodeFullReportXlsx(data);

    final fileName = _generateFileName(ExportType.fullReport, format);
    final rangeStr = _formatRangeString(data.from, data.to);

    await _recordAudit(
      type: ExportType.fullReport.name,
      format: format.name,
      rowCount: 1,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: 1,
      format: format,
      type: ExportType.fullReport,
    );
  }

  List<int> _encodeFullReportCsv(FullReportData data) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<dynamic>>[];

    // 1. RINGKASAN UTAMA
    rows.add(['=== RINGKASAN LAPORAN ===']);
    rows.add(['Metrik', 'Nilai']);
    rows.add(['Periode Awal', dateFmt.format(data.from.toLocal())]);
    rows.add(['Periode Akhir', dateFmt.format(data.to.toLocal())]);
    rows.add(['Omzet (Penjualan Bersih Kasir)', data.summary.omzet]);
    rows.add(['Pajak', data.summary.tax]);
    rows.add(['Pendapatan Bersih', data.summary.netRevenue]);
    rows.add(['Jumlah Transaksi', data.summary.txCount]);
    rows.add(['Rata-rata Nilai Transaksi', data.avgTxValue]);
    if (data.isProfitVisible) {
      rows.add(['HPP (Harga Pokok Penjualan)', data.summary.cogs ?? 0]);
      rows.add(['Laba Kotor', data.summary.grossProfit ?? 0]);
      rows.add(['Total Biaya Operasional', data.summary.totalExpenses]);
      rows.add(['Laba Bersih', data.summary.netProfit ?? 0]);
    }
    rows.add([]);

    // 2. PRODUK TERLARIS
    rows.add(['=== PRODUK TERLARIS ===']);
    rows.add([
      'Peringkat',
      'Nama Produk',
      'Jumlah Terjual (Qty)',
      'Total Omzet',
      if (data.isProfitVisible) 'Laba Kotor',
    ]);
    for (int i = 0; i < data.topProducts.length; i++) {
      final p = data.topProducts[i];
      rows.add([
        i + 1,
        p.productName,
        p.totalQty,
        p.totalRevenue,
        if (data.isProfitVisible) p.grossProfit ?? 0,
      ]);
    }
    rows.add([]);

    // 3. PENJUALAN PER KATEGORI
    rows.add(['=== PENJUALAN PER KATEGORI ===']);
    rows.add(['Kategori', 'Total Qty', 'Total Omzet', 'Kontribusi Omzet (%)']);
    for (final c in data.categorySales) {
      rows.add([
        c.categoryName,
        c.totalQty,
        c.totalRevenue,
        '${c.percentage.toStringAsFixed(1)}%',
      ]);
    }
    rows.add([]);

    // 4. PENJUALAN PER METODE PEMBAYARAN
    rows.add(['=== PENJUALAN PER METODE PEMBAYARAN ===']);
    rows.add(['Metode Pembayaran', 'Jumlah Transaksi', 'Total Omzet', 'Kontribusi Omzet (%)']);
    for (final pm in data.paymentMethodSales) {
      rows.add([
        pm.method,
        pm.txCount,
        pm.totalAmount,
        '${pm.percentage.toStringAsFixed(1)}%',
      ]);
    }
    rows.add([]);

    // 5. KINERJA KASIR (JIKA BUKAN SOLO)
    if (data.cashierSales != null && data.cashierSales!.isNotEmpty) {
      rows.add(['=== KINERJA KASIR ===']);
      rows.add(['Nama Kasir', 'Jumlah Transaksi', 'Total Omzet']);
      for (final cs in data.cashierSales!) {
        rows.add([cs.cashierName, cs.txCount, cs.totalRevenue]);
      }
      rows.add([]);
    }

    // 6. PENJUALAN PER JAM (JAM SIBUK)
    rows.add(['=== DISTRIBUSI PENJUALAN PER JAM ===']);
    rows.add(['Jam Operasional', 'Jumlah Transaksi', 'Total Omzet']);
    for (final h in data.hourlySales) {
      rows.add([h.hourLabel, h.txCount, h.totalRevenue]);
    }
    rows.add([]);

    // 7. VALUASI DAN STATUS STOK
    if (data.stockValuation != null) {
      rows.add(['=== VALUASI STOK GUDANG ===']);
      rows.add(['Metrik', 'Nilai']);
      rows.add(['Total Macam Produk', data.stockValuation!.totalProducts]);
      rows.add(['Total Unit Stok Fisik', data.stockValuation!.totalStockQty]);
      rows.add(['Total Nilai Jual Eceran', data.stockValuation!.totalRetailValue]);
      if (data.isProfitVisible) {
        rows.add(['Total Nilai Modal Stok', data.stockValuation!.totalCostValue ?? 0]);
        rows.add(['Potensi Laba Kotor', data.stockValuation!.potentialProfit ?? 0]);
      }
      rows.add([]);
    }

    // 8. RINGKASAN VOID
    rows.add(['=== RINGKASAN TRANSAKSI BATAL (VOID) ===']);
    rows.add(['Metrik', 'Nilai']);
    rows.add(['Jumlah Transaksi Batal', data.voidSummary.voidCount]);
    rows.add(['Total Nominal Dibatalkan', data.voidSummary.totalVoidAmount]);

    return _encodeCsvWithBom(rows);
  }

  List<int> _encodeFullReportXlsx(FullReportData data) {
    final excel = Excel.createExcel();
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    // Helper penulisan sheet
    void writeSheet(String sheetTitle, List<String> headers, List<List<dynamic>> rows) {
      final sheet = excel[sheetTitle];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
      for (final row in rows) {
        final cells = row.map<CellValue>((v) {
          if (v == null) return TextCellValue('');
          if (v is int) return IntCellValue(v);
          if (v is double) return DoubleCellValue(v);
          if (v is bool) return TextCellValue(v ? 'Ya' : 'Tidak');
          return TextCellValue(v.toString());
        }).toList();
        sheet.appendRow(cells);
      }
    }

    // 1. Sheet Ringkasan
    final summaryRows = <List<dynamic>>[
      ['Periode Awal', dateFmt.format(data.from.toLocal())],
      ['Periode Akhir', dateFmt.format(data.to.toLocal())],
      ['Omzet (Penjualan Selesai)', data.summary.omzet],
      ['Pajak', data.summary.tax],
      ['Pendapatan Bersih', data.summary.netRevenue],
      ['Jumlah Transaksi', data.summary.txCount],
      ['Rata-rata Transaksi', data.avgTxValue],
      if (data.isProfitVisible) ...[
        ['HPP (Harga Pokok Penjualan)', data.summary.cogs ?? 0],
        ['Laba Kotor', data.summary.grossProfit ?? 0],
        ['Total Biaya Operasional', data.summary.totalExpenses],
        ['Laba Bersih', data.summary.netProfit ?? 0],
      ],
      ['Jumlah Transaksi Void', data.voidSummary.voidCount],
      ['Total Nominal Void', data.voidSummary.totalVoidAmount],
    ];
    writeSheet('Ringkasan', ['Indikator Metrik', 'Nilai'], summaryRows);

    // 2. Sheet Produk Terlaris
    final topHeaders = [
      'Peringkat',
      'Nama Produk',
      'Jumlah Terjual (Qty)',
      'Total Omzet',
      if (data.isProfitVisible) 'Laba Kotor',
    ];
    final topRows = <List<dynamic>>[];
    for (int i = 0; i < data.topProducts.length; i++) {
      final p = data.topProducts[i];
      topRows.add([
        i + 1,
        p.productName,
        p.totalQty,
        p.totalRevenue,
        if (data.isProfitVisible) p.grossProfit ?? 0,
      ]);
    }
    writeSheet('Produk Terlaris', topHeaders, topRows);

    // 3. Sheet Kategori & Pembayaran
    final catHeaders = ['Kategori', 'Total Qty', 'Total Omzet', 'Persentase Omzet (%)'];
    final catRows = data.categorySales
        .map((c) => [c.categoryName, c.totalQty, c.totalRevenue, c.percentage])
        .toList();
    writeSheet('Kategori Penjualan', catHeaders, catRows);

    final pmHeaders = ['Metode Pembayaran', 'Jumlah Transaksi', 'Total Omzet', 'Persentase Omzet (%)'];
    final pmRows = data.paymentMethodSales
        .map((p) => [p.method, p.txCount, p.totalAmount, p.percentage])
        .toList();
    writeSheet('Metode Pembayaran', pmHeaders, pmRows);

    // 4. Sheet Kinerja Kasir & Jam Sibuk
    if (data.cashierSales != null && data.cashierSales!.isNotEmpty) {
      final csHeaders = ['Nama Kasir', 'Jumlah Transaksi', 'Total Omzet'];
      final csRows = data.cashierSales!
          .map((c) => [c.cashierName, c.txCount, c.totalRevenue])
          .toList();
      writeSheet('Kinerja Kasir', csHeaders, csRows);
    }

    final hourHeaders = ['Jam Operasional', 'Jumlah Transaksi', 'Total Omzet'];
    final hourRows = data.hourlySales
        .map((h) => [h.hourLabel, h.txCount, h.totalRevenue])
        .toList();
    writeSheet('Penjualan Per Jam', hourHeaders, hourRows);

    // 5. Sheet Valuasi & Status Stok
    if (data.stockValuation != null) {
      final valRows = <List<dynamic>>[
        ['Total Macam Produk', data.stockValuation!.totalProducts],
        ['Total Unit Stok Fisik', data.stockValuation!.totalStockQty],
        ['Total Nilai Jual Eceran', data.stockValuation!.totalRetailValue],
        if (data.isProfitVisible) ...[
          ['Total Modal Stok (HPP)', data.stockValuation!.totalCostValue ?? 0],
          ['Potensi Laba Kotor', data.stockValuation!.potentialProfit ?? 0],
        ],
      ];
      writeSheet('Valuasi Stok', ['Metrik Valuasi', 'Nilai'], valRows);
    }

    final alertHeaders = ['Status Stok', 'Nama Produk', 'Stok Saat Ini', 'Stok Minimum'];
    final alertRows = <List<dynamic>>[];
    for (final it in data.stockAlerts.outOfStockProducts) {
      alertRows.add(['HABIS (0)', it.name, it.currentStock, it.minStock]);
    }
    for (final it in data.stockAlerts.lowStockProducts) {
      alertRows.add(['MENIPIS', it.name, it.currentStock, it.minStock]);
    }
    writeSheet('Peringatan Stok', alertHeaders, alertRows);

    // Hapus Sheet default Sheet1 bawaan library
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    excel.setDefaultSheet('Ringkasan');

    return excel.save() ?? <int>[];
  }

  // =========================================================================
  // 7. EKSPOR LOG JEJAK AKTIVITAS (AUDIT LOGS)
  // =========================================================================

  Future<ExportResult> exportAuditLogs({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {
    _assertExportAccess();

    // Verifikasi izin khusus audit.view
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.auditView)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk melihat log aktivitas (audit.view).',
          code: 'FORBIDDEN',
        );
      }
    }

    final logs = await _auditDao.getLogsPage(
      limit: 1000000,
      startDate: from,
      endDate: to,
      category: category,
    );

    final userIds = logs.map((l) => l.userId).whereType<int>().toSet();
    final userNames = await _auditDao.getUserDisplayNames(userIds);

    final headers = <String>[
      'Waktu',
      'Pengguna',
      'Aksi',
      'Entitas',
      'ID Entitas',
      'Detail',
      'ID Perangkat',
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = logs.map((l) {
      final userName = l.userId != null ? (userNames[l.userId!] ?? 'User #${l.userId}') : 'Sistem';
      return [
        dateFmt.format(l.createdAt.toLocal()),
        userName,
        l.action,
        l.entity,
        l.entityId?.toString() ?? '',
        l.detail,
        l.deviceId,
      ];
    }).toList();

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Log Aktivitas', headers, rows);

    final fileName = _generateFileName(ExportType.auditLog, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.auditLog.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.auditLog,
    );
  }

  // =========================================================================
  // 8. EKSPOR PENGELUARAN OPERASIONAL
  // =========================================================================

  Future<ExportResult> exportExpenses({
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
    int? categoryId,
    String? status,
  }) async {
    _assertExportAccess();

    final entries = await _db.expenseDao.getExpensesPage(
      limit: 1000000,
      startDate: from,
      endDate: to,
      categoryId: categoryId,
      status: status,
    );

    final headers = <String>[
      'Tanggal',
      'Kategori',
      'Nominal',
      'Metode Pembayaran',
      'Status',
      'Catatan',
      'Dibuat Oleh',
      'Alasan Void',
      'Dibatalkan Oleh',
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = entries.map((e) {
      return [
        dateFmt.format(e.date.toLocal()),
        e.categoryName,
        e.amount,
        e.paymentMethod,
        e.status == 'void' ? 'Batal (Void)' : 'Aktif',
        e.note ?? '',
        e.createdByName,
        e.voidReason ?? '',
        e.voidedByName ?? '',
      ];
    }).toList();

    final bytes = format == ExportFormat.csv
        ? _encodeCsvWithBom([headers, ...rows])
        : _encodeXlsx('Pengeluaran', headers, rows);

    final fileName = _generateFileName(ExportType.expenses, format);
    final rangeStr = _formatRangeString(from, to);

    await _recordAudit(
      type: ExportType.expenses.name,
      format: format.name,
      rowCount: rows.length,
      range: rangeStr,
    );

    return ExportResult(
      fileName: fileName,
      bytes: bytes,
      rowCount: rows.length,
      format: format,
      type: ExportType.expenses,
    );
  }

  String _formatRangeString(DateTime? from, DateTime? to) {
    if (from != null && to != null) {
      final f = DateFormat('yyyyMMdd').format(from);
      final t = DateFormat('yyyyMMdd').format(to);
      return '$f-$t';
    }
    return 'all';
  }
}

