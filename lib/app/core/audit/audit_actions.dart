import 'dart:convert';
import '../utils/currency_formatter.dart';

/// Katalog konstanta aksi jejak audit (Audit Actions) sistem POS Me.
abstract class AuditActions {
  AuditActions._();

  // --- Produk ---
  static const productCreate = 'product.create';
  static const productUpdate = 'product.update';
  static const productPriceChange = 'product.price_change';
  static const productDeactivate = 'product.deactivate';
  static const productActivate = 'product.activate';

  // --- Kategori & Satuan ---
  static const categoryCreate = 'category.create';
  static const categoryUpdate = 'category.update';
  static const categoryDelete = 'category.delete';

  static const unitCreate = 'unit.create';
  static const unitUpdate = 'unit.update';
  static const unitDelete = 'unit.delete';

  // --- Stok ---
  static const stockAdjust = 'stock.adjust';
  static const stockOpnameFinalize = 'stock.opname_finalize';
  static const stockPurchaseReceive = 'stock.purchase_receive';
  static const stockPurchaseCancel = 'stock.purchase_cancel';

  // --- Penjualan (POS) ---
  static const saleVoid = 'sale.void';
  static const saleReturn = 'sale.return';
  static const saleDiscountHigh = 'sale.discount_high';

  // --- Autentikasi & Akun Kasir ---
  static const authLogin = 'auth.login';
  static const authLoginFailed = 'auth.login_failed';
  static const authLogout = 'auth.logout';
  static const authPasswordChanged = 'auth.password_changed';
  static const authRecoveryUsed = 'auth.recovery_used';

  // --- Pengeluaran Operasional ---
  static const expenseCreate = 'expense.create';
  static const expenseUpdate = 'expense.update';
  static const expenseVoid = 'expense.void';

  // --- Pelanggan & Kasbon ---
  static const customerCreate = 'customer.create';
  static const customerUpdate = 'customer.update';
  static const customerDeactivate = 'customer.deactivate';
  static const customerCreditSale = 'customer.credit_sale';
  static const customerPaymentReceived = 'customer.payment_received';

  // --- Manajemen Pengguna / Karyawan (Fase 2) ---
  static const userCreate = 'user.create';
  static const userUpdate = 'user.update';
  static const userRoleChanged = 'user.role_changed';
  static const userPasswordReset = 'user.password_reset';
  static const userDeactivate = 'user.deactivate';

  // --- Pengaturan & Sistem ---
  static const settingsUpdate = 'settings.update';
  static const licenseTierChanged = 'license.tier_changed';
  static const backupCreate = 'backup.create';
  static const backupRestore = 'backup.restore';
  static const importRun = 'import.run';
  static const exportRun = 'export.run';

  /// Kategori umum untuk filter di UI
  static const List<String> categories = [
    'Semua',
    'Produk',
    'Stok',
    'Penjualan',
    'Pelanggan',
    'Akun',
    'Pengaturan',
    'Sistem',
  ];

  /// Mengelompokkan action ke dalam kategori UI
  static String getCategory(String action) {
    if (action.startsWith('product.')) return 'Produk';
    if (action.startsWith('stock.')) return 'Stok';
    if (action.startsWith('sale.')) return 'Penjualan';
    if (action.startsWith('customer.')) return 'Pelanggan';
    if (action.startsWith('auth.') || action.startsWith('user.')) return 'Akun';
    if (action.startsWith('settings.') || action.startsWith('license.')) return 'Pengaturan';
    if (action.startsWith('category.') ||
        action.startsWith('unit.') ||
        action.startsWith('backup.') ||
        action.startsWith('import.') ||
        action.startsWith('export.')) {
      return 'Sistem';
    }
    return 'Lainnya';
  }

  /// Memformat teks naratif bahasa Indonesia yang mudah dibaca untuk setiap log aktivitas
  static String formatHumanSentence({
    required String action,
    required String userName,
    dynamic detail,
  }) {
    Map<String, dynamic> d = const {};
    if (detail is Map<String, dynamic>) {
      d = detail;
    } else if (detail is Map) {
      d = Map<String, dynamic>.from(detail);
    } else if (detail is String && detail.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(detail);
        if (decoded is Map) {
          d = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    switch (action) {
      case productCreate:
        final name = d['name'] ?? d['productName'] ?? 'produk baru';
        return '$userName menambahkan produk baru "$name"';

      case productUpdate:
        final name = d['name'] ?? d['productName'] ?? 'produk';
        final diffs = <String>[];
        if (d.containsKey('diff') && d['diff'] is Map) {
          final diffMap = d['diff'] as Map;
          for (final key in diffMap.keys) {
            final change = diffMap[key];
            if (change is Map) {
              final oldVal = change['old'];
              final newVal = change['new'];
              if (key == 'sellPrice') {
                diffs.add('harga jual: ${formatRupiah(oldVal ?? 0)} -> ${formatRupiah(newVal ?? 0)}');
              } else if (key == 'costPrice') {
                diffs.add('harga beli: ${formatRupiah(oldVal ?? 0)} -> ${formatRupiah(newVal ?? 0)}');
              } else {
                diffs.add('$key: $oldVal -> $newVal');
              }
            }
          }
        } else if (d.containsKey('oldSellPrice') && d.containsKey('newSellPrice')) {
          diffs.add('harga jual: ${formatRupiah(d['oldSellPrice'] ?? 0)} -> ${formatRupiah(d['newSellPrice'] ?? 0)}');
        }
        if (diffs.isNotEmpty) {
          return '$userName mengubah data produk "$name" (${diffs.join(', ')})';
        }
        return '$userName memperbarui data produk "$name"';

      case productPriceChange:
        final name = d['productName'] ?? 'produk';
        final oldP = formatRupiah(d['oldSellPrice'] ?? 0);
        final newP = formatRupiah(d['newSellPrice'] ?? 0);
        return '$userName mengubah harga jual "$name" dari $oldP menjadi $newP';

      case productDeactivate:
        final name = d['name'] ?? d['productName'] ?? 'produk';
        return '$userName menonaktifkan produk "$name"';

      case productActivate:
        final name = d['name'] ?? d['productName'] ?? 'produk';
        return '$userName mengaktifkan kembali produk "$name"';

      case stockAdjust:
      case 'stock.adjustment':
        final name = d['productName'] ?? d['product'] ?? 'produk';
        final oldS = d['oldStock'] ?? d['sebelum'] ?? '?';
        final newS = d['newStock'] ?? d['sesudah'] ?? '?';
        final reason = d['reason'] ?? d['alasan'] ?? d['note'] ?? '-';
        return '$userName menyesuaikan stok "$name" dari $oldS menjadi $newS (Alasan: $reason)';

      case stockOpnameFinalize:
        final code = d['code'] ?? d['opnameCode'] ?? '';
        final diffCount = d['diffCount'] ?? d['totalDifferenceItems'] ?? 0;
        final totalValue = formatRupiah(d['totalDiffValue'] ?? 0);
        return '$userName memfinalisasi Stock Opname $code ($diffCount item selisih, nilai: $totalValue)';

      case stockPurchaseReceive:
        final no = d['refNo'] ?? d['purchaseNo'] ?? '-';
        final total = formatRupiah(d['total'] ?? 0);
        return '$userName menerima barang dari pembelian $no (Total: $total)';

      case stockPurchaseCancel:
        final no = d['refNo'] ?? d['purchaseNo'] ?? '-';
        final r = d['reason'] ?? '-';
        return '$userName membatalkan pembelian $no (Alasan: $r)';

      case saleVoid:
        final inv = d['invoiceNo'] ?? '-';
        final r = d['reason'] ?? '-';
        return '$userName membatalkan (VOID) nota $inv (Alasan: $r)';

      case saleReturn:
        final inv = d['invoiceNo'] ?? '-';
        final rtnNo = d['returnNo'] ?? '-';
        final total = formatRupiah(d['total'] ?? d['totalRefund'] ?? 0);
        final r = d['reason'] ?? '-';
        return '$userName memproses retur $rtnNo untuk nota $inv sebesar $total (Alasan: $r)';

      case saleDiscountHigh:
        final inv = d['invoiceNo'] ?? '-';
        final disc = formatRupiah(d['discount'] ?? 0);
        return '$userName memberikan diskon besar $disc pada nota $inv';

      case authLogin:
        return '$userName berhasil masuk ke aplikasi (Login)';

      case authLoginFailed:
        final userAttempt = d['username'] ?? 'tidak diketahui';
        return 'Percobaan masuk gagal untuk akun "$userAttempt"';

      case authLogout:
        return '$userName keluar dari sesi aplikasi (Logout)';

      case authPasswordChanged:
        return '$userName memperbarui kata sandi / PIN akun';

      case authRecoveryUsed:
        return '$userName menggunakan kode pemulihan darurat';

      case expenseCreate:
        final cat = d['category'] ?? d['categoryName'] ?? 'Operasional';
        final amt = formatRupiah(d['amount'] ?? 0);
        return '$userName mencatat pengeluaran $cat sebesar $amt';

      case expenseUpdate:
        final cat = d['category'] ?? d['categoryName'] ?? 'Operasional';
        final amt = formatRupiah(d['amount'] ?? 0);
        final oldAmt = d['oldAmount'] != null ? formatRupiah(d['oldAmount'] ?? 0) : null;
        if (oldAmt != null && oldAmt != amt) {
          return '$userName mengubah pengeluaran $cat dari $oldAmt menjadi $amt';
        }
        return '$userName memperbarui data pengeluaran $cat ($amt)';

      case expenseVoid:
        final cat = d['category'] ?? d['categoryName'] ?? 'Operasional';
        final amt = formatRupiah(d['amount'] ?? 0);
        final reason = d['reason'] ?? '-';
        return '$userName membatalkan pengeluaran $cat sebesar $amt (Alasan: $reason)';

      case customerCreate:
        final name = d['name'] ?? 'pelanggan';
        return '$userName menambahkan pelanggan baru "$name"';

      case customerUpdate:
        final name = d['name'] ?? 'pelanggan';
        return '$userName memperbarui data pelanggan "$name"';

      case customerDeactivate:
        final name = d['name'] ?? 'pelanggan';
        return '$userName menonaktifkan pelanggan "$name"';

      case customerCreditSale:
        final name = d['customerName'] ?? 'pelanggan';
        final amount = d['amount'] is int ? formatRupiah(d['amount'] as int) : 'Rp ${d['amount']}';
        final inv = d['invoiceNo'] != null ? ' (${d['invoiceNo']})' : '';
        return '$userName mencatat penjualan kasbon ke "$name" sebesar $amount$inv';

      case customerPaymentReceived:
        final name = d['customerName'] ?? 'pelanggan';
        final amount = d['amount'] is int ? formatRupiah(d['amount'] as int) : 'Rp ${d['amount']}';
        final method = d['method'] ?? 'cash';
        return '$userName menerima pelunasan kasbon dari "$name" sebesar $amount via $method';

      case settingsUpdate:
        final keys = d['updatedKeys'] ?? d['keys'] ?? 'konfigurasi';
        return '$userName memperbarui pengaturan sistem ($keys)';

      case licenseTierChanged:
        final tier = d['tier'] ?? d['newTier'] ?? 'baru';
        return 'Lisensi sistem diperbarui ke tier $tier';

      case backupCreate:
        return '$userName membuat berkas cadangan data (Backup)';

      case backupRestore:
        return '$userName memulihkan data dari berkas cadangan (Restore)';

      case importRun:
        final count = d['count'] ?? 0;
        return '$userName mengimpor data ($count baris berhasil)';

      case exportRun:
        return '$userName mengekspor data ke file spreadsheet';

      default:
        final act = action.replaceAll('.', ' ');
        return '$userName melakukan aksi $act';
    }
  }

  /// Membantu membersihkan detail dari data sensitif (password, PIN, hash, dll.)
  static Map<String, dynamic> sanitizeDetail(Map<String, dynamic> raw) {
    final sanitized = Map<String, dynamic>.from(raw);
    const forbiddenKeys = [
      'password',
      'pass',
      'pin',
      'hash',
      'secret',
      'token',
      'recoveryCode',
      'recovery_code',
      'recovery_hash',
    ];

    for (final k in forbiddenKeys) {
      sanitized.remove(k);
    }
    return sanitized;
  }
}

