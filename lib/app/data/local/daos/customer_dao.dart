import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_payments.dart';
import '../tables/customers.dart';
import '../tables/payments.dart';
import '../tables/sale_returns.dart';
import '../tables/sales.dart';

part 'customer_dao.g.dart';

/// Data kelas representasi pelanggan beserta saldo kasbon yang dihitung dinamis.
class CustomerWithBalance {
  final Customer customer;
  final int balance; // Saldo hutang aktif (Rupiah int, >= 0)

  const CustomerWithBalance({
    required this.customer,
    required this.balance,
  });

  int get id => customer.id;
  String get uuid => customer.uuid;
  String get name => customer.name;
  String? get phone => customer.phone;
  String? get address => customer.address;
  String? get note => customer.note;
  int? get creditLimit => customer.creditLimit;
  bool get isActive => customer.isActive;
  DateTime get createdAt => customer.createdAt;
  DateTime get updatedAt => customer.updatedAt;

  bool get hasDebt => balance > 0;
  int? get remainingLimit =>
      creditLimit != null ? (creditLimit! - balance).clamp(0, creditLimit!) : null;
}

/// Item riwayat transaksi hutang pelanggan (Buku Pembantu Piutang / Ledger).
class CustomerLedgerItem {
  final DateTime date;
  final String type; // 'credit_sale' | 'payment' | 'credit_return'
  final String refNo; // Invoice No / Return No / ID Pembayaran
  final int debit; // Menambah hutang (+)
  final int credit; // Mengurangi hutang (-)
  final int balanceAfter; // Saldo berjalan setelah transaksi
  final String? note;
  final String? method; // Metode pembayaran untuk type == 'payment'

  const CustomerLedgerItem({
    required this.date,
    required this.type,
    required this.refNo,
    required this.debit,
    required this.credit,
    required this.balanceAfter,
    this.note,
    this.method,
  });
}

/// Rekap umur piutang per pelanggan (Aging Report).
class CustomerAgingItem {
  final Customer customer;
  final int totalBalance;
  final DateTime? oldestUnpaidDate;
  final int ageDays;
  final int bucket0to7;
  final int bucket8to30;
  final int bucketOver30;

  const CustomerAgingItem({
    required this.customer,
    required this.totalBalance,
    this.oldestUnpaidDate,
    required this.ageDays,
    required this.bucket0to7,
    required this.bucket8to30,
    required this.bucketOver30,
  });
}

@DriftAccessor(tables: [Customers, CustomerPayments, Sales, Payments, SaleReturns])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  /// Menambah pelanggan baru.
  Future<int> insertCustomer(CustomersCompanion companion) =>
      into(customers).insert(companion);

  /// Memperbarui data pelanggan.
  Future<bool> updateCustomer(CustomersCompanion companion) =>
      update(customers).replace(companion);

  /// Mengambil data pelanggan murni berdasarkan ID.
  Future<Customer?> getCustomerById(int id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Mengambil data pelanggan berdasarkan UUID.
  Future<Customer?> getCustomerByUuid(String uuid) =>
      (select(customers)..where((c) => c.uuid.equals(uuid))).getSingleOrNull();

  /// Menghitung saldo kasbon pelanggan saat ini secara dinamis dari database.
  /// Saldo = (Total Kasbon dari Sales completed) - (Total Pembayaran Kasbon) - (Porsi Retur Kasbon)
  Future<int> getCustomerBalance(int customerId) async {
    // 1. Total kasbon dari transaksi penjualan status completed
    final creditSalesRow = await customSelect(
      'SELECT COALESCE(SUM(p.amount), 0) AS total_credit '
      'FROM payments p '
      'INNER JOIN sales s ON p.sale_id = s.id '
      "WHERE s.customer_id = ? AND s.status = 'completed' AND p.method = 'credit'",
      variables: [Variable<int>(customerId)],
      readsFrom: {sales, payments},
    ).getSingleOrNull();
    final totalCredit = creditSalesRow?.read<int>('total_credit') ?? 0;

    // 2. Total pembayaran pelunasan dari customer_payments
    final paymentsRow = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total_paid '
      'FROM customer_payments '
      'WHERE customer_id = ?',
      variables: [Variable<int>(customerId)],
      readsFrom: {customerPayments},
    ).getSingleOrNull();
    final totalPaid = paymentsRow?.read<int>('total_paid') ?? 0;

    // 3. Total retur yang mengurangi kasbon (credit_refund)
    final returnsRow = await customSelect(
      'SELECT COALESCE(SUM(sr.credit_refund), 0) AS total_credit_refund '
      'FROM sale_returns sr '
      'INNER JOIN sales s ON sr.sale_id = s.id '
      "WHERE s.customer_id = ? AND s.status = 'completed'",
      variables: [Variable<int>(customerId)],
      readsFrom: {sales, saleReturns},
    ).getSingleOrNull();
    final totalCreditRefund = returnsRow?.read<int>('total_credit_refund') ?? 0;

    final balance = totalCredit - totalPaid - totalCreditRefund;
    return balance < 0 ? 0 : balance;
  }

  /// Mengambil pelanggan lengkap beserta saldo kasbonnya.
  Future<CustomerWithBalance?> getCustomerWithBalance(int id) async {
    final customer = await getCustomerById(id);
    if (customer == null) return null;
    final balance = await getCustomerBalance(id);
    return CustomerWithBalance(customer: customer, balance: balance);
  }

  /// Mencari daftar pelanggan dengan opsi filter pencarian dan "punya hutang".
  Future<List<CustomerWithBalance>> getCustomersWithBalances({
    String? query,
    bool onlyWithDebt = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmedQuery = query?.trim();
    final searchPattern = (trimmedQuery != null && trimmedQuery.isNotEmpty)
        ? '%$trimmedQuery%'
        : null;

    final rows = await customSelect(
      'SELECT '
      '  c.id, c.uuid, c.device_id, c.name, c.phone, c.address, c.note, '
      '  c.credit_limit, c.is_active, c.created_at, c.updated_at, '
      '  (COALESCE(cs.total_credit, 0) - COALESCE(cp.total_paid, 0) - COALESCE(cr.total_refund, 0)) AS balance '
      'FROM customers c '
      'LEFT JOIN ('
      '  SELECT s.customer_id, SUM(p.amount) AS total_credit '
      '  FROM payments p '
      '  INNER JOIN sales s ON p.sale_id = s.id '
      "  WHERE s.status = 'completed' AND p.method = 'credit' "
      '  GROUP BY s.customer_id '
      ') cs ON c.id = cs.customer_id '
      'LEFT JOIN ('
      '  SELECT customer_id, SUM(amount) AS total_paid '
      '  FROM customer_payments '
      '  GROUP BY customer_id '
      ') cp ON c.id = cp.customer_id '
      'LEFT JOIN ('
      '  SELECT s.customer_id, SUM(sr.credit_refund) AS total_refund '
      '  FROM sale_returns sr '
      '  INNER JOIN sales s ON sr.sale_id = s.id '
      "  WHERE s.status = 'completed' "
      '  GROUP BY s.customer_id '
      ') cr ON c.id = cr.customer_id '
      'WHERE (?1 IS NULL OR c.name LIKE ?1 OR c.phone LIKE ?1) '
      '  AND (?2 = 0 OR (COALESCE(cs.total_credit, 0) - COALESCE(cp.total_paid, 0) - COALESCE(cr.total_refund, 0)) > 0) '
      'ORDER BY c.name COLLATE NOCASE ASC '
      'LIMIT ?3 OFFSET ?4',
      variables: [
        Variable<String>(searchPattern),
        Variable<int>(onlyWithDebt ? 1 : 0),
        Variable<int>(limit),
        Variable<int>(offset),
      ],
      readsFrom: {customers, sales, payments, customerPayments, saleReturns},
    ).get();

    return rows.map((r) {
      final customer = Customer(
        id: r.read<int>('id'),
        uuid: r.read<String>('uuid'),
        deviceId: r.read<String>('device_id'),
        name: r.read<String>('name'),
        phone: r.read<String?>('phone'),
        address: r.read<String?>('address'),
        note: r.read<String?>('note'),
        creditLimit: r.read<int?>('credit_limit'),
        isActive: r.read<bool>('is_active'),
        createdAt: r.read<DateTime>('created_at'),
        updatedAt: r.read<DateTime>('updated_at'),
      );
      final rawBal = r.read<int>('balance');
      final balance = rawBal < 0 ? 0 : rawBal;
      return CustomerWithBalance(customer: customer, balance: balance);
    }).toList();
  }

  /// Memeriksa apakah pelanggan sudah memiliki transaksi (penjualan kasir atau pembayaran).
  Future<bool> hasTransactions(int customerId) async {
    final saleCountRow = await customSelect(
      'SELECT COUNT(*) AS count FROM sales WHERE customer_id = ?',
      variables: [Variable<int>(customerId)],
      readsFrom: {sales},
    ).getSingleOrNull();

    final paymentCountRow = await customSelect(
      'SELECT COUNT(*) AS count FROM customer_payments WHERE customer_id = ?',
      variables: [Variable<int>(customerId)],
      readsFrom: {customerPayments},
    ).getSingleOrNull();

    final saleCount = saleCountRow?.read<int>('count') ?? 0;
    final paymentCount = paymentCountRow?.read<int>('count') ?? 0;
    return (saleCount + paymentCount) > 0;
  }

  /// Menonaktifkan pelanggan (isActive = false).
  Future<int> deactivateCustomer(int id) {
    return (update(customers)..where((c) => c.id.equals(id))).write(
      const CustomersCompanion(isActive: Value(false)),
    );
  }

  /// Mengaktifkan kembali pelanggan (isActive = true).
  Future<int> activateCustomer(int id) {
    return (update(customers)..where((c) => c.id.equals(id))).write(
      const CustomersCompanion(isActive: Value(true)),
    );
  }

  /// Menghapus pelanggan (hanya jika belum memiliki transaksi).
  Future<int> deleteCustomer(int id) {
    return (delete(customers)..where((c) => c.id.equals(id))).go();
  }

  /// Menambahkan pencatatan pelunasan hutang (customer_payments).
  Future<int> insertCustomerPayment(CustomerPaymentsCompanion companion) =>
      into(customerPayments).insert(companion);

  /// Mengambil daftar riwayat transaksi kasbon, pelunasan, dan retur untuk seorang pelanggan.
  Future<List<CustomerLedgerItem>> getCustomerLedger(int customerId) async {
    // 1. Ambil transaksi kasbon
    final creditSales = await customSelect(
      'SELECT s.id, s.invoice_no, s.created_at, p.amount '
      'FROM payments p '
      'INNER JOIN sales s ON p.sale_id = s.id '
      "WHERE s.customer_id = ? AND s.status = 'completed' AND p.method = 'credit'",
      variables: [Variable<int>(customerId)],
      readsFrom: {sales, payments},
    ).get();

    // 2. Ambil pelunasan hutang
    final paymentsRows = await customSelect(
      'SELECT id, uuid, created_at, amount, method, note '
      'FROM customer_payments '
      'WHERE customer_id = ?',
      variables: [Variable<int>(customerId)],
      readsFrom: {customerPayments},
    ).get();

    // 3. Ambil retur penjualan yang memotong kasbon
    final returnRows = await customSelect(
      'SELECT sr.id, sr.return_no, sr.created_at, sr.credit_refund, sr.reason '
      'FROM sale_returns sr '
      'INNER JOIN sales s ON sr.sale_id = s.id '
      "WHERE s.customer_id = ? AND s.status = 'completed' AND sr.credit_refund > 0",
      variables: [Variable<int>(customerId)],
      readsFrom: {sales, saleReturns},
    ).get();

    // Gabungkan dalam satu deretan peristiwa dan urutkan secara kronologis (waktu naik)
    final events = <_RawLedgerEvent>[];

    for (final r in creditSales) {
      events.add(_RawLedgerEvent(
        date: r.read<DateTime>('created_at'),
        type: 'credit_sale',
        refNo: r.read<String>('invoice_no'),
        debit: r.read<int>('amount'),
        credit: 0,
        note: 'Penjualan Kasbon (${r.read<String>('invoice_no')})',
      ));
    }

    for (final r in paymentsRows) {
      events.add(_RawLedgerEvent(
        date: r.read<DateTime>('created_at'),
        type: 'payment',
        refNo: 'BAYAR-${r.read<int>('id')}',
        debit: 0,
        credit: r.read<int>('amount'),
        note: r.read<String?>('note') ?? 'Pelunasan Kasbon',
        method: r.read<String>('method'),
      ));
    }

    for (final r in returnRows) {
      events.add(_RawLedgerEvent(
        date: r.read<DateTime>('created_at'),
        type: 'credit_return',
        refNo: r.read<String>('return_no'),
        debit: 0,
        credit: r.read<int>('credit_refund'),
        note: 'Retur Kasbon: ${r.read<String>('reason')}',
      ));
    }

    // Urutkan dari terlama ke terbaru untuk menghitung saldo berjalan dengan tepat
    events.sort((a, b) => a.date.compareTo(b.date));

    int runningBalance = 0;
    final result = <CustomerLedgerItem>[];

    for (final ev in events) {
      runningBalance += ev.debit;
      runningBalance -= ev.credit;
      if (runningBalance < 0) runningBalance = 0;

      result.add(CustomerLedgerItem(
        date: ev.date,
        type: ev.type,
        refNo: ev.refNo,
        debit: ev.debit,
        credit: ev.credit,
        balanceAfter: runningBalance,
        note: ev.note,
        method: ev.method,
      ));
    }

    // Kembalikan dalam urutan terbaru di atas untuk kemudahan baca di UI
    return result.reversed.toList();
  }

  /// Mengambil total piutang aktif seluruh toko.
  Future<int> getTotalReceivables() async {
    final row = await customSelect(
      'SELECT '
      '  COALESCE(SUM(balance), 0) AS total_receivables '
      'FROM ('
      '  SELECT '
      '    (COALESCE(cs.total_credit, 0) - COALESCE(cp.total_paid, 0) - COALESCE(cr.total_refund, 0)) AS balance '
      '  FROM customers c '
      '  LEFT JOIN ('
      '    SELECT s.customer_id, SUM(p.amount) AS total_credit '
      '    FROM payments p '
      '    INNER JOIN sales s ON p.sale_id = s.id '
      "    WHERE s.status = 'completed' AND p.method = 'credit' "
      '    GROUP BY s.customer_id '
      '  ) cs ON c.id = cs.customer_id '
      '  LEFT JOIN ('
      '    SELECT customer_id, SUM(amount) AS total_paid '
      '    FROM customer_payments '
      '    GROUP BY customer_id '
      '  ) cp ON c.id = cp.customer_id '
      '  LEFT JOIN ('
      '    SELECT s.customer_id, SUM(sr.credit_refund) AS total_refund '
      '    FROM sale_returns sr '
      '    INNER JOIN sales s ON sr.sale_id = s.id '
      "    WHERE s.status = 'completed' "
      '    GROUP BY s.customer_id '
      '  ) cr ON c.id = cr.customer_id '
      '  WHERE (COALESCE(cs.total_credit, 0) - COALESCE(cp.total_paid, 0) - COALESCE(cr.total_refund, 0)) > 0 '
      ')',
      readsFrom: {customers, sales, payments, customerPayments, saleReturns},
    ).getSingleOrNull();

    return row?.read<int>('total_receivables') ?? 0;
  }

  /// Menghitung laporan umur piutang (Aging Report) per pelanggan.
  Future<List<CustomerAgingItem>> getAgingReport() async {
    final customersWithDebt = await getCustomersWithBalances(onlyWithDebt: true, limit: 500);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final agingList = <CustomerAgingItem>[];

    for (final item in customersWithDebt) {
      if (item.balance <= 0) continue;

      // Ambil transaksi kasbon belum lunas secara FIFO
      final creditSales = await customSelect(
        'SELECT s.id, s.invoice_no, s.created_at, p.amount '
        'FROM payments p '
        'INNER JOIN sales s ON p.sale_id = s.id '
        "WHERE s.customer_id = ? AND s.status = 'completed' AND p.method = 'credit' "
        'ORDER BY s.created_at ASC',
        variables: [Variable<int>(item.id)],
        readsFrom: {sales, payments},
      ).get();

      // Total pengurangan (pembayaran + retur)
      final reductionsRow = await customSelect(
        'SELECT '
        '  (COALESCE(cp.total_paid, 0) + COALESCE(cr.total_refund, 0)) AS total_reduced '
        'FROM customers c '
        'LEFT JOIN ('
        '  SELECT customer_id, SUM(amount) AS total_paid '
        '  FROM customer_payments WHERE customer_id = ?1 '
        ') cp ON 1=1 '
        'LEFT JOIN ('
        '  SELECT s.customer_id, SUM(sr.credit_refund) AS total_refund '
        '  FROM sale_returns sr '
        '  INNER JOIN sales s ON sr.sale_id = s.id '
        "  WHERE s.customer_id = ?1 AND s.status = 'completed' "
        ') cr ON 1=1 '
        'WHERE c.id = ?1',
        variables: [Variable<int>(item.id)],
        readsFrom: {customerPayments, saleReturns, sales},
      ).getSingleOrNull();

      int remainingReductions = reductionsRow?.read<int>('total_reduced') ?? 0;

      DateTime? oldestUnpaidDate;
      int bucket0to7 = 0;
      int bucket8to30 = 0;
      int bucketOver30 = 0;

      for (final sRow in creditSales) {
        final saleAmt = sRow.read<int>('amount');
        final saleDate = sRow.read<DateTime>('created_at');

        if (remainingReductions >= saleAmt) {
          remainingReductions -= saleAmt;
          continue; // Invoice ini sudah terlunasi penuh oleh pengurangan sebelumnya
        }

        final unpaidPortion = saleAmt - remainingReductions;
        remainingReductions = 0;

        oldestUnpaidDate ??= saleDate;

        final daysDiff = today.difference(DateTime(saleDate.year, saleDate.month, saleDate.day)).inDays;
        if (daysDiff <= 7) {
          bucket0to7 += unpaidPortion;
        } else if (daysDiff <= 30) {
          bucket8to30 += unpaidPortion;
        } else {
          bucketOver30 += unpaidPortion;
        }
      }

      final oldestDays = oldestUnpaidDate != null
          ? today.difference(DateTime(oldestUnpaidDate.year, oldestUnpaidDate.month, oldestUnpaidDate.day)).inDays
          : 0;

      agingList.add(CustomerAgingItem(
        customer: item.customer,
        totalBalance: item.balance,
        oldestUnpaidDate: oldestUnpaidDate,
        ageDays: oldestDays < 0 ? 0 : oldestDays,
        bucket0to7: bucket0to7,
        bucket8to30: bucket8to30,
        bucketOver30: bucketOver30,
      ));
    }

    return agingList;
  }
}

class _RawLedgerEvent {
  final DateTime date;
  final String type;
  final String refNo;
  final int debit;
  final int credit;
  final String? note;
  final String? method;

  const _RawLedgerEvent({
    required this.date,
    required this.type,
    required this.refNo,
    required this.debit,
    required this.credit,
    this.note,
    this.method,
  });
}

