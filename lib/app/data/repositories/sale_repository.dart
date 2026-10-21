import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/tax/tax_calculator.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/sale_dao.dart';
import '../local/daos/stock_dao.dart';
import 'stock_repository.dart';

class CheckoutCartItem {
  final int productId;
  final String productName;
  final int qty;
  final int price; // Snapshot harga jual (Rupiah)
  final int costPrice; // Snapshot harga beli (Rupiah)
  final int discount; // Diskon per satuan item (Rupiah)

  const CheckoutCartItem({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.price,
    required this.costPrice,
    this.discount = 0,
  });

  int get subtotal => (price - discount) * qty;
}

class CheckoutPayment {
  final String method; // 'cash' | 'qris' | 'transfer' | 'other'
  final int amount;

  const CheckoutPayment({required this.method, required this.amount});
}

class CheckoutResult {
  final Sale sale;
  final List<SaleItem> items;
  final List<Payment> payments;

  const CheckoutResult({
    required this.sale,
    required this.items,
    required this.payments,
  });
}

/// Transaksi tersimpan lengkap dengan item, pembayaran, dan nama kasir.
class SaleDetail {
  final Sale sale;
  final List<SaleItem> items;
  final List<Payment> payments;
  final String cashierName;
  final String? voidedByName;

  const SaleDetail({
    required this.sale,
    required this.items,
    required this.payments,
    required this.cashierName,
    this.voidedByName,
  });
}

/// Satu baris pada daftar riwayat transaksi.
class SaleListEntry {
  final Sale sale;
  final String cashierName;

  /// Metode pembayaran unik (urutan sesuai pencatatan): 'cash', 'qris', dst.
  final List<String> paymentMethods;

  const SaleListEntry({
    required this.sale,
    required this.cashierName,
    required this.paymentMethods,
  });
}

class SaleRepository {
  final AppDatabase _db;
  final SaleDao _saleDao;
  final ProductDao _productDao;
  final StockDao _stockDao;
  final StockRepository _stockRepo;

  SaleRepository(
    this._db,
    this._saleDao,
    this._productDao,
    this._stockDao, [
    StockRepository? stockRepo,
  ]) : _stockRepo = stockRepo ?? StockRepository(_db, _stockDao, _productDao);

  // Backward-compatible constructor for existing tests
  SaleRepository.withDaoOnly(this._saleDao, [StockRepository? stockRepo])
    : _db = _saleDao.attachedDatabase,
      _productDao = _saleDao.attachedDatabase.productDao,
      _stockDao = _saleDao.attachedDatabase.stockDao,
      _stockRepo =
          stockRepo ??
          StockRepository(
            _saleDao.attachedDatabase,
            _saleDao.attachedDatabase.stockDao,
            _saleDao.attachedDatabase.productDao,
          );

  Future<List<Sale>> getAllSales() => _saleDao.getAllSales();
  Stream<List<Sale>> watchAllSales() => _saleDao.watchAllSales();
  Future<Sale?> getSaleById(int id) => _saleDao.getSaleById(id);
  Future<Sale?> getSaleByInvoice(String invoiceNo) =>
      _saleDao.getSaleByInvoice(invoiceNo);
  Future<int> insertSale(SalesCompanion sale) => _saleDao.insertSale(sale);
  Future<bool> updateSale(SalesCompanion sale) => _saleDao.updateSale(sale);
  Future<int> insertSaleItem(SaleItemsCompanion item) =>
      _saleDao.insertSaleItem(item);
  Future<List<SaleItem>> getItemsBySaleId(int saleId) =>
      _saleDao.getItemsBySaleId(saleId);
  Future<int> insertPayment(PaymentsCompanion payment) =>
      _saleDao.insertPayment(payment);
  Future<List<Payment>> getPaymentsBySaleId(int saleId) =>
      _saleDao.getPaymentsBySaleId(saleId);

  /// Menentukan ID kasir efektif:
  /// Jika pengguna tidak memiliki izin 'pos.view_all_sales', kueri dipaksa HANYA
  /// mengambil transaksi miliknya sendiri untuk mencegah kebocoran data.
  int? _enforceCashierFilter(int? requestedCashierId) {
    if (Get.isRegistered<PermissionService>()) {
      final canViewAll = PermissionService.to.can(PermissionKeys.posViewAllSales);
      if (!canViewAll) {
        final currentUserId = Get.isRegistered<AuthService>()
            ? AuthService.to.currentUser.value?.id
            : null;
        return currentUserId;
      }
    }
    return requestedCashierId;
  }

  /// Detail lengkap satu transaksi tersimpan (untuk layar sukses, detail riwayat,
  /// dan cetak ulang). Mengembalikan null bila id tidak ditemukan.
  Future<SaleDetail?> getSaleDetail(int saleId) async {
    final sale = await _saleDao.getSaleById(saleId);
    if (sale == null) return null;

    if (Get.isRegistered<PermissionService>()) {
      final canViewAll = PermissionService.to.can(PermissionKeys.posViewAllSales);
      final currentUserId = Get.isRegistered<AuthService>()
          ? AuthService.to.currentUser.value?.id
          : null;
      if (!canViewAll && currentUserId != null && sale.cashierId != currentUserId) {
        throw const AppException('Akses ditolak: Anda hanya dapat melihat detail transaksi Anda sendiri.');
      }
    }

    final items = await _saleDao.getItemsBySaleId(saleId);
    final payments = await _saleDao.getPaymentsBySaleId(saleId);

    final userIds = <int>{sale.cashierId};
    if (sale.voidedBy != null) userIds.add(sale.voidedBy!);
    final names = await _saleDao.getUserDisplayNames(userIds);

    return SaleDetail(
      sale: sale,
      items: items,
      payments: payments,
      cashierName: names[sale.cashierId] ?? '-',
      voidedByName: sale.voidedBy != null ? names[sale.voidedBy] : null,
    );
  }

  /// Satu halaman riwayat (terbaru di atas) lengkap dengan nama kasir dan metode
  /// pembayaran. Mendukung filter tanggal, status, kasir, dan pencarian invoice.
  Future<List<SaleListEntry>> getSalesPage({
    int limit = 30,
    SalesCursor? after,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? searchQuery,
    int? cashierId,
  }) async {
    final effectiveCashierId = _enforceCashierFilter(cashierId);
    final sales = await _saleDao.getSalesPage(
      limit: limit,
      after: after,
      startDate: startDate,
      endDate: endDate,
      status: status,
      searchQuery: searchQuery,
      cashierId: effectiveCashierId,
    );
    if (sales.isEmpty) return const <SaleListEntry>[];

    final payments = await _saleDao.getPaymentsBySaleIds(
      sales.map((s) => s.id),
    );
    final userIds = sales.map((s) => s.cashierId).toSet();
    for (final s in sales) {
      if (s.voidedBy != null) userIds.add(s.voidedBy!);
    }
    final names = await _saleDao.getUserDisplayNames(userIds);

    final methodsBySale = <int, List<String>>{};
    for (final payment in payments) {
      final methods = methodsBySale.putIfAbsent(
        payment.saleId,
        () => <String>[],
      );
      if (!methods.contains(payment.method)) methods.add(payment.method);
    }

    return sales
        .map(
          (sale) => SaleListEntry(
            sale: sale,
            cashierName: names[sale.cashierId] ?? '-',
            paymentMethods: methodsBySale[sale.id] ?? const <String>[],
          ),
        )
        .toList();
  }

  /// Ringkasan harian (agregat SQL, tanggal lokal) untuk rentang [from, to).
  Future<List<DailySalesSummary>> getDailySummaries({
    required DateTime from,
    required DateTime to,
    String? status,
    String? searchQuery,
    int? cashierId,
  }) {
    final effectiveCashierId = _enforceCashierFilter(cashierId);
    return _saleDao.getDailySummaries(
      from: from,
      to: to,
      status: status,
      searchQuery: searchQuery,
      cashierId: effectiveCashierId,
    );
  }

  /// Ringkasan total agregat untuk keseluruhan filter yang aktif di atas list.
  Future<DailySalesSummary> getAggregateSummary({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? searchQuery,
    int? cashierId,
  }) {
    final effectiveCashierId = _enforceCashierFilter(cashierId);
    return _saleDao.getAggregateSummary(
      startDate: startDate,
      endDate: endDate,
      status: status,
      searchQuery: searchQuery,
      cashierId: effectiveCashierId,
    );
  }

  /// Membatalkan transaksi (VOID) dalam SATU database.transaction():
  /// 1. Cek izin can('pos.void') di repository layer
  /// 2. Pastikan status masih 'completed' (cegah double void)
  /// 3. Validasi alasan pembatalan (wajib min 5 karakter)
  /// 4. Tandai status 'void', voidReason, voidedBy, voidedAt
  /// 5. Kembalikan stok item via StockRepository.applyMovement (type: 'void', qtyChange: +qty)
  ///    (produk nonaktif atau terkunci tier tetap dikembalikan stoknya)
  /// 6. Catat log ke AuditService
  /// 7. Gagal sebagian = rollback total
  Future<Sale> voidSale({
    required int saleId,
    required String reason,
    int? voidedByUserId,
  }) async {
    // 1. Cek izin di repository layer (Two-layer enforcement)
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.posVoid)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk membatalkan transaksi (pos.void).',
          code: 'FORBIDDEN_VOID',
        );
      }
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.length < 5) {
      throw const AppException(
        'Alasan pembatalan (void) wajib diisi minimal 5 karakter.',
        code: 'INVALID_VOID_REASON',
      );
    }

    final currentUserId =
        voidedByUserId ??
        (Get.isRegistered<AuthService>()
            ? AuthService.to.currentUser.value?.id
            : null);

    return await _db.transaction(() async {
      // 2. Ambil transaksi & pastikan berstatus 'completed'
      final sale = await _saleDao.getSaleById(saleId);
      if (sale == null) {
        throw AppException(
          'Transaksi dengan ID $saleId tidak ditemukan.',
          code: 'SALE_NOT_FOUND',
        );
      }

      if (sale.status == 'void') {
        throw const AppException(
          'Transaksi ini sudah dibatalkan (void) sebelumnya.',
          code: 'ALREADY_VOIDED',
        );
      }

      if (sale.status != 'completed') {
        throw AppException(
          'Hanya transaksi berstatus selesai yang dapat dibatalkan (Status: ${sale.status}).',
          code: 'INVALID_STATUS_FOR_VOID',
        );
      }

      final hasReturns = await _db.saleReturnDao.hasReturnsForSale(saleId);
      if (hasReturns) {
        throw const AppException(
          'Transaksi yang sudah memiliki retur tidak dapat dibatalkan (void).',
          code: 'SALE_HAS_RETURNS',
        );
      }

      final now = DateTime.now();

      // 3. Set status=void, voidReason, voidedBy, voidedAt
      await _saleDao.markSaleAsVoid(
        saleId: sale.id,
        reason: trimmedReason,
        voidedBy: currentUserId,
        voidedAt: now,
      );

      // 4. Kembalikan stok untuk setiap item di snapshot sale_items
      final items = await _saleDao.getItemsBySaleId(saleId);
      for (final item in items) {
        await _stockRepo.applyMovement(
          productId: item.productId,
          type: 'void',
          qtyChange: item
              .qty, // Positif: mengembalikan stok yang berkurang saat checkout
          refTable: 'sales',
          refId: sale.id,
          note: 'Void ${sale.invoiceNo}: $trimmedReason',
          createdBy: currentUserId,
        );
      }

      // 5. Catat jejak audit
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'sale.void',
          entity: 'sales',
          entityId: sale.id,
          detail: {
            'invoiceNo': sale.invoiceNo,
            'reason': trimmedReason,
            'total': sale.total,
            'voidedBy': currentUserId,
            'voidedAt': now.toIso8601String(),
          },
        );
      }

      return (await _saleDao.getSaleById(saleId))!;
    });
  }

  /// Menghasilkan nomor invoice unik berurutan per hari dengan prefix deviceId:
  /// Format: INV-YYYYMMDD-DEV-NNNN (reset ke 0001 setiap hari baru)
  Future<String> generateInvoiceNo(String deviceId, {DateTime? date}) async {
    final now = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final cleanDev = deviceId.replaceAll('-', '').trim();
    final shortDev =
        (cleanDev.length >= 4 ? cleanDev.substring(0, 4) : cleanDev)
            .toUpperCase();
    final prefix = 'INV-$dateStr-$shortDev-';

    final count = await _saleDao.countSalesByPrefix(prefix);
    int seq = count + 1;
    String candidate = '$prefix${seq.toString().padLeft(4, '0')}';

    // Pastikan benar-benar unik (tidak ada tabrakan)
    while (await _saleDao.getSaleByInvoice(candidate) != null) {
      seq++;
      candidate = '$prefix${seq.toString().padLeft(4, '0')}';
    }

    return candidate;
  }

  /// Menyimpan transaksi checkout POS secara ATOMIK dalam satu database.transaction():
  /// 1. Validasi kecukupan stok (bila allowNegativeStock == false)
  /// 2. Snapshot produk (nama, harga jual, harga beli) ke sale_items
  /// 3. Catat sales (uuid, deviceId, invoiceNo, subtotal, discount, total, paid, change)
  /// 4. Catat payments (mendukung split payment)
  /// 5. Catat mutasi stok (stock_movements type 'sale') per item
  /// 6. Kurangi currentStock produk
  /// Jika ada langkah yang gagal, SELURUH transaksi di-rollback secara otomatis.
  Future<CheckoutResult> checkout({
    required int cashierId,
    required String deviceId,
    required List<CheckoutCartItem> items,
    required List<CheckoutPayment> payments,
    int overallDiscount = 0,
    int tax = 0,
    int? taxRateBps,
    String? taxMode,
    bool allowNegativeStock = false,
    DateTime? transactionTime,
  }) async {
    if (items.isEmpty) {
      throw const AppException('Keranjang belanja kosong.');
    }

    return await _db.transaction(() async {
      // 1. Validasi kuantitas & stok setiap produk
      for (final item in items) {
        if (item.qty <= 0) {
          throw AppException(
            'Jumlah kuantitas untuk "${item.productName}" harus lebih dari 0.',
          );
        }

        final product = await _productDao.getProductById(item.productId);
        if (product == null) {
          throw AppException(
            'Produk "${item.productName}" (ID ${item.productId}) tidak ditemukan.',
          );
        }

        if (!product.isActive) {
          throw AppException(
            'Produk "${product.name}" sedang berstatus nonaktif.',
          );
        }

        if (!allowNegativeStock && product.currentStock < item.qty) {
          throw AppException(
            'Stok produk "${product.name}" tidak mencukupi.\n(Tersedia: ${product.currentStock}, Diminta: ${item.qty}).',
            code: 'INSUFFICIENT_STOCK',
          );
        }
      }

      // 2. Hitung total angka keuangan
      int subtotal = 0;
      int itemsDiscount = 0;
      for (final item in items) {
        subtotal += item.price * item.qty;
        itemsDiscount += item.discount * item.qty;
      }

      final totalDiscount = itemsDiscount + overallDiscount;
      final netBasis = (subtotal - totalDiscount).clamp(0, 999999999999);

      final int effectiveTax;
      final int totalAmount;

      if (taxRateBps != null && taxRateBps > 0 && taxMode != null) {
        final calc = TaxCalculator.calculate(
          basis: netBasis,
          rateBps: taxRateBps,
          mode: taxMode,
          isEnabled: true,
        );
        effectiveTax = calc.tax;
        totalAmount = calc.total;
      } else {
        effectiveTax = tax;
        totalAmount = (taxMode == 'inclusive' ? netBasis : (netBasis + tax))
            .clamp(0, 999999999999);
      }

      final totalPaid = payments.fold<int>(0, (sum, p) => sum + p.amount);
      if (totalPaid < totalAmount) {
        throw AppException(
          'Pembayaran kurang. Tagihan: Rp $totalAmount, Dibayarkan: Rp $totalPaid.',
          code: 'UNDERPAID',
        );
      }
      final changeAmount = totalPaid - totalAmount;

      // 3. Generate invoice & UUID
      final now = transactionTime ?? DateTime.now();
      final invoiceNo = await generateInvoiceNo(deviceId, date: now);
      final saleUuid = const Uuid().v4();

      // 4. Insert Sales
      final saleId = await _saleDao.insertSale(
        SalesCompanion(
          uuid: Value(saleUuid),
          deviceId: Value(deviceId),
          invoiceNo: Value(invoiceNo),
          cashierId: Value(cashierId),
          subtotal: Value(subtotal),
          discount: Value(totalDiscount),
          tax: Value(effectiveTax),
          taxRateBps: Value(taxRateBps),
          taxMode: Value(taxMode),
          total: Value(totalAmount),
          paid: Value(totalPaid),
          change: Value(changeAmount),
          status: const Value('completed'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // 5. Insert SaleItems (Snapshot) & Kurangi Stok
      final insertedItems = <SaleItem>[];
      for (final item in items) {
        final product = await _productDao.getProductById(item.productId);
        final costPrice = product?.costPrice ?? item.costPrice;

        final itemId = await _saleDao.insertSaleItem(
          SaleItemsCompanion(
            saleId: Value(saleId),
            productId: Value(item.productId),
            productName: Value(item.productName),
            qty: Value(item.qty),
            price: Value(item.price),
            costPrice: Value(costPrice),
            discount: Value(item.discount),
            subtotal: Value(item.subtotal),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        insertedItems.add(
          SaleItem(
            id: itemId,
            saleId: saleId,
            productId: item.productId,
            productName: item.productName,
            qty: item.qty,
            price: item.price,
            costPrice: costPrice,
            discount: item.discount,
            subtotal: item.subtotal,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // 6. Catat mutasi stok (stock_movements type 'sale')
        await _stockDao.insertMovement(
          StockMovementsCompanion.insert(
            uuid: const Uuid().v4(),
            productId: item.productId,
            type: 'sale',
            qtyChange: -item.qty,
            refTable: const Value('sales'),
            refId: Value(saleId),
            note: Value('Penjualan $invoiceNo'),
            createdBy: Value(cashierId),
          ),
        );

        // 7. Update currentStock di tabel products
        final currentStock = product?.currentStock ?? 0;
        await _productDao.updateProductStock(
          item.productId,
          currentStock - item.qty,
        );
      }

      // 8. Insert Payments
      final insertedPayments = <Payment>[];
      for (final payment in payments) {
        final paymentId = await _saleDao.insertPayment(
          PaymentsCompanion(
            saleId: Value(saleId),
            method: Value(payment.method),
            amount: Value(payment.amount),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        insertedPayments.add(
          Payment(
            id: paymentId,
            saleId: saleId,
            method: payment.method,
            amount: payment.amount,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      final createdSale = Sale(
        id: saleId,
        uuid: saleUuid,
        deviceId: deviceId,
        invoiceNo: invoiceNo,
        cashierId: cashierId,
        subtotal: subtotal,
        discount: totalDiscount,
        tax: effectiveTax,
        taxRateBps: taxRateBps,
        taxMode: taxMode,
        total: totalAmount,
        paid: totalPaid,
        change: changeAmount,
        status: 'completed',
        createdAt: now,
        updatedAt: now,
      );

      return CheckoutResult(
        sale: createdSale,
        items: insertedItems,
        payments: insertedPayments,
      );
    });
  }
}
