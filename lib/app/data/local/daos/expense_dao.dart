import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/expense_categories.dart';
import '../tables/expenses.dart';
import '../tables/users.dart';

part 'expense_dao.g.dart';

/// Data kelas gabungan entitas pengeluaran beserta relasi kategori dan penggunanya.
class ExpenseWithCategory {
  final Expense expense;
  final String categoryName;
  final String createdByName;
  final String? voidedByName;

  const ExpenseWithCategory({
    required this.expense,
    required this.categoryName,
    required this.createdByName,
    this.voidedByName,
  });

  int get id => expense.id;
  String get uuid => expense.uuid;
  DateTime get date => expense.date;
  int get categoryId => expense.categoryId;
  int get amount => expense.amount;
  String? get note => expense.note;
  String get paymentMethod => expense.paymentMethod;
  String get status => expense.status;
  bool get isVoided => expense.status == 'void';
  String? get voidReason => expense.voidReason;
  DateTime? get voidedAt => expense.voidedAt;
  DateTime get createdAt => expense.createdAt;
}

/// Rekap agregasi pengeluaran per kategori dalam periode tertentu.
class ExpenseCategoryAggregate {
  final int categoryId;
  final String categoryName;
  final int totalAmount;
  final int count;

  const ExpenseCategoryAggregate({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.count,
  });
}

@DriftAccessor(tables: [ExpenseCategories, Expenses, Users])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  static const List<String> defaultCategoryNames = [
    'Listrik',
    'Air',
    'Sewa',
    'Gaji',
    'Transport',
    'Kemasan',
    'Perawatan',
    'Lainnya',
  ];

  // ===================== KATEGORI PENGELUARAN =====================

  /// Mengambil semua kategori pengeluaran terurut nama.
  Future<List<ExpenseCategory>> getAllCategories() =>
      (select(expenseCategories)..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

  /// Mengambil kategori pengeluaran yang aktif saja.
  Future<List<ExpenseCategory>> getActiveCategories() =>
      (select(expenseCategories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  /// Mengambil kategori berdasarkan ID.
  Future<ExpenseCategory?> getCategoryById(int id) =>
      (select(expenseCategories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Mengambil kategori berdasarkan nama.
  Future<ExpenseCategory?> getCategoryByName(String name) =>
      (select(expenseCategories)..where((c) => c.name.equals(name.trim()))).getSingleOrNull();

  /// Menyimpan kategori baru.
  Future<int> insertCategory(ExpenseCategoriesCompanion category) =>
      into(expenseCategories).insert(category);

  /// Memperbarui kategori.
  Future<bool> updateCategory(ExpenseCategoriesCompanion category) =>
      update(expenseCategories).replace(category);

  /// Menghapus kategori berdasarkan ID.
  Future<int> deleteCategory(int id) =>
      (delete(expenseCategories)..where((c) => c.id.equals(id))).go();

  /// Memeriksa apakah kategori sedang digunakan oleh catatan pengeluaran (baik aktif maupun void).
  Future<bool> isCategoryUsed(int categoryId) async {
    final countExp = expenses.id.count();
    final query = selectOnly(expenses)
      ..addColumns([countExp])
      ..where(expenses.categoryId.equals(categoryId));
    final row = await query.getSingle();
    return (row.read(countExp) ?? 0) > 0;
  }

  /// Seeder kategori default (idempotent, hanya menambahkan yang belum ada).
  Future<void> seedDefaultCategories() async {
    for (final name in defaultCategoryNames) {
      final existing = await getCategoryByName(name);
      if (existing == null) {
        await insertCategory(
          ExpenseCategoriesCompanion.insert(
            uuid: const Uuid().v4(),
            name: name,
            isActive: const Value(true),
          ),
        );
      }
    }
  }

  // ===================== TRANSAKSI PENGELUARAN =====================

  /// Menyimpan transaksi pengeluaran baru.
  Future<int> insertExpense(ExpensesCompanion expense) =>
      into(expenses).insert(expense);

  /// Memperbarui data transaksi pengeluaran (misal nominal, kategori, catatan, dll).
  Future<bool> updateExpense(ExpensesCompanion expense) =>
      update(expenses).replace(expense);

  /// Mengambil data pengeluaran berdasarkan ID.
  Future<Expense?> getExpenseById(int id) =>
      (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Mengambil detail pengeluaran lengkap dengan relasi kategori dan pembuatnya.
  Future<ExpenseWithCategory?> getExpenseWithCategory(int id) async {
    final creator = alias(users, 'creator');
    final voider = alias(users, 'voider');

    final query = select(expenses).join([
      innerJoin(expenseCategories, expenseCategories.id.equalsExp(expenses.categoryId)),
      innerJoin(creator, creator.id.equalsExp(expenses.createdBy)),
      leftOuterJoin(voider, voider.id.equalsExp(expenses.voidedBy)),
    ])..where(expenses.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    final exp = row.readTable(expenses);
    final cat = row.readTable(expenseCategories);
    final crUser = row.readTable(creator);
    final vdUser = row.readTableOrNull(voider);

    return ExpenseWithCategory(
      expense: exp,
      categoryName: cat.name,
      createdByName: crUser.displayName,
      voidedByName: vdUser?.displayName,
    );
  }

  /// Membatalkan (void) transaksi pengeluaran.
  Future<bool> voidExpense({
    required int id,
    required String reason,
    required int voidedBy,
    DateTime? voidedAt,
  }) async {
    final now = voidedAt ?? DateTime.now();
    final updatedRows = await (update(expenses)..where((e) => e.id.equals(id))).write(
      ExpensesCompanion(
        status: const Value('void'),
        voidReason: Value(reason),
        voidedBy: Value(voidedBy),
        voidedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return updatedRows > 0;
  }

  /// Mengambil daftar pengeluaran dengan pagination dan filter.
  Future<List<ExpenseWithCategory>> getExpensesPage({
    DateTime? startDate,
    DateTime? endDate,
    int? categoryId,
    String? status, // 'active' / 'void' / null (semua)
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    final creator = alias(users, 'creator');
    final voider = alias(users, 'voider');

    final query = select(expenses).join([
      innerJoin(expenseCategories, expenseCategories.id.equalsExp(expenses.categoryId)),
      innerJoin(creator, creator.id.equalsExp(expenses.createdBy)),
      leftOuterJoin(voider, voider.id.equalsExp(expenses.voidedBy)),
    ]);

    Expression<bool> predicate = const Constant(true);

    if (startDate != null) {
      predicate &= expenses.date.isBiggerOrEqualValue(startDate);
    }
    if (endDate != null) {
      predicate &= expenses.date.isSmallerOrEqualValue(endDate);
    }
    if (categoryId != null) {
      predicate &= expenses.categoryId.equals(categoryId);
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      predicate &= expenses.status.equals(status);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      predicate &= (expenses.note.like(term) | expenseCategories.name.like(term));
    }

    query
      ..where(predicate)
      ..orderBy([
        OrderingTerm.desc(expenses.date),
        OrderingTerm.desc(expenses.id),
      ])
      ..limit(limit, offset: offset);

    final rows = await query.get();
    return rows.map((row) {
      return ExpenseWithCategory(
        expense: row.readTable(expenses),
        categoryName: row.readTable(expenseCategories).name,
        createdByName: row.readTable(creator).displayName,
        voidedByName: row.readTableOrNull(voider)?.displayName,
      );
    }).toList();
  }

  /// Menghitung total nominal pengeluaran berstatus 'active' dalam rentang [from, to).
  Future<int> getTotalExpensesForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final sumExp = expenses.amount.sum();
    final query = selectOnly(expenses)
      ..addColumns([sumExp])
      ..where(
        expenses.status.equals('active') &
            expenses.date.isBiggerOrEqualValue(from) &
            expenses.date.isSmallerThanValue(to),
      );

    final row = await query.getSingle();
    return row.read(sumExp) ?? 0;
  }

  /// Menghitung jumlah transaksi pengeluaran berstatus 'active' dalam rentang [from, to).
  Future<int> countActiveExpensesForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final countExp = expenses.id.count();
    final query = selectOnly(expenses)
      ..addColumns([countExp])
      ..where(
        expenses.status.equals('active') &
            expenses.date.isBiggerOrEqualValue(from) &
            expenses.date.isSmallerThanValue(to),
      );

    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Mengambil rincian pengeluaran aktif per kategori dalam rentang waktu [from, to).
  Future<List<ExpenseCategoryAggregate>> getExpenseCategoryBreakdown({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await customSelect(
      'SELECT '
      'ec.id AS category_id, '
      'ec.name AS category_name, '
      'COALESCE(SUM(e.amount), 0) AS total_amount, '
      'COUNT(e.id) AS expense_count '
      'FROM expense_categories ec '
      'INNER JOIN expenses e ON ec.id = e.category_id '
      "WHERE e.status = 'active' "
      '  AND e.date >= ? '
      '  AND e.date < ? '
      'GROUP BY ec.id, ec.name '
      'ORDER BY total_amount DESC',
      variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
      readsFrom: {expenseCategories, expenses},
    ).get();

    return rows.map((r) {
      return ExpenseCategoryAggregate(
        categoryId: r.read<int>('category_id'),
        categoryName: r.read<String>('category_name'),
        totalAmount: r.read<int>('total_amount'),
        count: r.read<int>('expense_count'),
      );
    }).toList();
  }
}

