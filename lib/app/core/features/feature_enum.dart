/// Daftar fitur aplikasi POS Me yang dikontrol melalui sistem lisensi / tier.
enum Feature {
  unlimitedProducts,
  stockOpname,
  purchases,
  importExport,
  fullReports,
  autoBackup,
  expenses,
  customerCredit,
  teamManagement,
  attendance,
  customRoles,
  hostClient,
  shifts,
  voidApproval;

  String get displayName {
    switch (this) {
      case Feature.unlimitedProducts:
        return 'Produk Tanpa Batas';
      case Feature.stockOpname:
        return 'Stock Opname';
      case Feature.purchases:
        return 'Pembelian & Suplier';
      case Feature.importExport:
        return 'Import & Export Data';
      case Feature.fullReports:
        return 'Laporan Laba & Analisis Penuh';
      case Feature.autoBackup:
        return 'Pencadangan Otomatis';
      case Feature.expenses:
        return 'Pengeluaran Operasional';
      case Feature.customerCredit:
        return 'Pelanggan & Kasbon';
      case Feature.teamManagement:
        return 'Multi-User & Tim Kasir';
      case Feature.attendance:
        return 'Absensi Karyawan';
      case Feature.customRoles:
        return 'Kustomisasi Role & Izin';
      case Feature.hostClient:
        return 'Sinkronisasi Multi-Device (Host/Client)';
      case Feature.shifts:
        return 'Manajemen Shift Kasir';
      case Feature.voidApproval:
        return 'Otorisasi Void Transaksi';
    }
  }
}

