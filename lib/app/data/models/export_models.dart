/// Format berkas yang didukung untuk ekspor data.
enum ExportFormat {
  csv,
  xlsx;

  String get displayName {
    switch (this) {
      case ExportFormat.csv:
        return 'CSV (.csv)';
      case ExportFormat.xlsx:
        return 'Excel Spreadsheet (.xlsx)';
    }
  }

  String get extension => this == ExportFormat.csv ? 'csv' : 'xlsx';
}

/// Jenis-jenis entitas dan laporan yang dapat diekspor.
enum ExportType {
  product,
  sales,
  stockCard,
  stockOpname,
  purchases,
  fullReport,
  auditLog,
  expenses,
  customers,
  receivables;

  String get displayName {
    switch (this) {
      case ExportType.product:
        return 'Katalog Produk';
      case ExportType.sales:
        return 'Laporan & Rincian Penjualan';
      case ExportType.stockCard:
        return 'Kartu Stok & Mutasi';
      case ExportType.stockOpname:
        return 'Hasil Stock Opname';
      case ExportType.purchases:
        return 'Data Pembelian & Kulakan';
      case ExportType.fullReport:
        return 'Laporan Lengkap Komprehensif';
      case ExportType.auditLog:
        return 'Log Jejak Aktivitas (Audit)';
      case ExportType.expenses:
        return 'Pengeluaran Operasional';
      case ExportType.customers:
        return 'Data Pelanggan';
      case ExportType.receivables:
        return 'Daftar & Umur Piutang';
    }
  }

  String get filePrefix {
    switch (this) {
      case ExportType.product:
        return 'katalog_produk';
      case ExportType.sales:
        return 'rincian_penjualan';
      case ExportType.stockCard:
        return 'kartu_stok';
      case ExportType.stockOpname:
        return 'hasil_opname';
      case ExportType.purchases:
        return 'data_pembelian';
      case ExportType.fullReport:
        return 'laporan_lengkap';
      case ExportType.auditLog:
        return 'log_aktivitas';
      case ExportType.expenses:
        return 'pengeluaran_operasional';
      case ExportType.customers:
        return 'data_pelanggan';
      case ExportType.receivables:
        return 'daftar_piutang';
    }
  }
}

/// Parameter filter untuk proses ekspor data.
class ExportFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? status;
  final String? searchQuery;
  final int? productId;
  final int? supplierId;
  final int? opnameId;
  final String? category;

  const ExportFilter({
    this.startDate,
    this.endDate,
    this.status,
    this.searchQuery,
    this.productId,
    this.supplierId,
    this.opnameId,
    this.category,
  });

  String get rangeDescription {
    if (startDate != null && endDate != null) {
      final s = '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}';
      final e = '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}';
      return '${s}_sd_$e';
    }
    return 'semua_waktu';
  }
}

/// Hasil dari proses ekspor berkas data.
class ExportResult {
  final String fileName;
  final List<int> bytes;
  final int rowCount;
  final ExportFormat format;
  final ExportType type;

  const ExportResult({
    required this.fileName,
    required this.bytes,
    required this.rowCount,
    required this.format,
    required this.type,
  });
}

