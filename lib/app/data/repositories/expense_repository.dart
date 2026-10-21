import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/device_id_service.dart';
import '../local/app_database.dart';
import '../local/daos/expense_dao.dart';

class CreateExpenseInput {
  final DateTime date;
  final int categoryId;
  final int amount;
  final String? note;
  final String paymentMethod; // 'cash' | 'transfer' | 'other'
  final String? deviceId;

  const CreateExpenseInput({
    required this.date,
    required this.categoryId,
    required this.amount,
    this.note,
    this.paymentMethod = 'cash',
    this.deviceId,
  });
}

class UpdateExpenseInput {
  final int id;
  final DateTime date;
  final int categoryId;
  final int amount;
  final String? note;
  final String paymentMethod;

  const UpdateExpenseInput({
    required this.id,
    required this.date,
    required this.categoryId,
    required this.amount,
    this.note,
    this.paymentMethod = 'cash',
  });
}

class ExpenseRepository {
  final AppDatabase _db;
  final ExpenseDao _expenseDao;
  final FeatureGate? _featureGate;
  final PermissionService? _permissionService;
  final AuditService? _auditService;

  ExpenseRepository(
    this._db,
    this._expenseDao, {
    FeatureGate? featureGate,
    PermissionService? permissionService,
    AuditService? auditService,
  })  : _featureGate = featureGate,
        _permissionService = permissionService,
        _auditService = auditService;

  AppDatabase get db => _db;

  bool _isFeatureEnabled() {
    if (_featureGate != null) {
      return _featureGate.isEnabled(Feature.expenses);
    }
    if (Get.isRegistered<FeatureGate>()) {
      return FeatureGate.to.isEnabled(Feature.expenses);
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

  void _enforceViewAccess() {
    if (!_isFeatureEnabled()) {
      throw const AppException(
        'Fitur Pengeluaran Operasional memerlukan lisensi Semi-Premium ke atas.',
        code: 'FEATURE_LOCKED',
      );
    }
    if (!_hasPermission(PermissionKeys.expenseView)) {
      throw const AppException(
        'Akses ditolak: Anda tidak memiliki izin melihat data pengeluaran (expense.view).',
        code: 'FORBIDDEN',
      );
    }
  }

  void _enforceManageAccess() {
    if (!_isFeatureEnabled()) {
      throw const AppException(
        'Fitur Pengeluaran Operasional memerlukan lisensi Semi-Premium ke atas.',
        code: 'FEATURE_LOCKED',
      );
    }
    if (!_hasPermission(PermissionKeys.expenseManage)) {
      throw const AppException(
        'Akses ditolak: Anda tidak memiliki izin mengelola pengeluaran (expense.manage).',
        code: 'FORBIDDEN',
      );
    }
  }

  // ===================== KATEGORI =====================

  Future<List<ExpenseCategory>> getAllCategories() async {
    _enforceViewAccess();
    return _expenseDao.getAllCategories();
  }

  Future<List<ExpenseCategory>> getActiveCategories() async {
    _enforceViewAccess();
    return _expenseDao.getActiveCategories();
  }

  Future<ExpenseCategory> createCategory(String name) async {
    _enforceManageAccess();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Nama kategori tidak boleh kosong.');
    }

    final existing = await _expenseDao.getCategoryByName(trimmed);
    if (existing != null) {
      if (!existing.isActive) {
        // Reaktifkan kategori jika sebelumnya nonaktif
        await _expenseDao.updateCategory(
          existing.toCompanion(true).copyWith(isActive: const Value(true)),
        );
        return (await _expenseDao.getCategoryById(existing.id))!;
      }
      throw AppException('Kategori "$trimmed" sudah terdaftar.');
    }

    final id = await _expenseDao.insertCategory(
      ExpenseCategoriesCompanion.insert(
        uuid: const Uuid().v4(),
        name: trimmed,
        isActive: const Value(true),
      ),
    );

    return (await _expenseDao.getCategoryById(id))!;
  }

  Future<ExpenseCategory> updateCategory(int id, {required String name, required bool isActive}) async {
    _enforceManageAccess();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Nama kategori tidak boleh kosong.');
    }

    final category = await _expenseDao.getCategoryById(id);
    if (category == null) {
      throw const AppException('Kategori tidak ditemukan.');
    }

    final duplicate = await _expenseDao.getCategoryByName(trimmed);
    if (duplicate != null && duplicate.id != id) {
      throw AppException('Kategori "$trimmed" sudah digunakan.');
    }

    await _expenseDao.updateCategory(
      ExpenseCategoriesCompanion(
        id: Value(id),
        uuid: Value(category.uuid),
        name: Value(trimmed),
        isActive: Value(isActive),
        createdAt: Value(category.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return (await _expenseDao.getCategoryById(id))!;
  }

  Future<void> deleteCategory(int id) async {
    _enforceManageAccess();
    final isUsed = await _expenseDao.isCategoryUsed(id);
    if (isUsed) {
      throw const AppException(
        'Kategori tidak dapat dihapus karena sudah pernah digunakan dalam transaksi pengeluaran. Anda dapat menonaktifkannya.',
        code: 'CATEGORY_IN_USE',
      );
    }
    await _expenseDao.deleteCategory(id);
  }

  // ===================== PENGELUARAN =====================

  Future<ExpenseWithCategory> createExpense(CreateExpenseInput input) async {
    _enforceManageAccess();

    if (input.amount <= 0) {
      throw const AppException(
        'Nominal pengeluaran harus lebih besar dari 0.',
        code: 'INVALID_AMOUNT',
      );
    }

    final category = await _expenseDao.getCategoryById(input.categoryId);
    if (category == null || !category.isActive) {
      throw const AppException('Kategori pengeluaran tidak valid atau nonaktif.');
    }

    final currentUserId = Get.isRegistered<AuthService>()
        ? (AuthService.to.currentUser.value?.id ?? 1)
        : 1;

    final deviceId = input.deviceId ??
        (Get.isRegistered<DeviceIdService>()
            ? DeviceIdService.to.deviceId
            : 'default-device');

    final now = DateTime.now();
    final uuid = const Uuid().v4();

    final id = await _expenseDao.insertExpense(
      ExpensesCompanion.insert(
        uuid: uuid,
        deviceId: deviceId,
        date: input.date,
        categoryId: input.categoryId,
        amount: input.amount,
        note: Value(input.note?.trim()),
        paymentMethod: Value(input.paymentMethod),
        status: const Value('active'),
        createdBy: currentUserId,
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // Audit log
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    await audit?.log(
      action: AuditActions.expenseCreate,
      entity: 'expenses',
      entityId: id,
      detail: {
        'amount': input.amount,
        'category': category.name,
        'categoryId': category.id,
        'date': input.date.toIso8601String(),
        'note': input.note,
        'paymentMethod': input.paymentMethod,
      },
    );

    return (await _expenseDao.getExpenseWithCategory(id))!;
  }

  Future<ExpenseWithCategory> updateExpense(UpdateExpenseInput input) async {
    _enforceManageAccess();

    if (input.amount <= 0) {
      throw const AppException(
        'Nominal pengeluaran harus lebih besar dari 0.',
        code: 'INVALID_AMOUNT',
      );
    }

    final existing = await _expenseDao.getExpenseById(input.id);
    if (existing == null) {
      throw const AppException('Data pengeluaran tidak ditemukan.');
    }

    if (existing.status == 'void') {
      throw const AppException('Pengeluaran yang sudah dibatalkan (void) tidak dapat diubah.');
    }

    final category = await _expenseDao.getCategoryById(input.categoryId);
    if (category == null) {
      throw const AppException('Kategori pengeluaran tidak valid.');
    }

    final oldAmount = existing.amount;
    final oldNote = existing.note;
    final now = DateTime.now();

    await _expenseDao.updateExpense(
      ExpensesCompanion(
        id: Value(existing.id),
        uuid: Value(existing.uuid),
        deviceId: Value(existing.deviceId),
        date: Value(input.date),
        categoryId: Value(input.categoryId),
        amount: Value(input.amount),
        note: Value(input.note?.trim()),
        paymentMethod: Value(input.paymentMethod),
        status: Value(existing.status),
        voidReason: Value(existing.voidReason),
        voidedBy: Value(existing.voidedBy),
        voidedAt: Value(existing.voidedAt),
        createdBy: Value(existing.createdBy),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(now),
      ),
    );

    // Audit log perubahan
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    await audit?.log(
      action: AuditActions.expenseUpdate,
      entity: 'expenses',
      entityId: existing.id,
      detail: {
        'oldAmount': oldAmount,
        'amount': input.amount,
        'oldCategoryId': existing.categoryId,
        'newCategoryId': input.categoryId,
        'category': category.name,
        'oldNote': oldNote,
        'newNote': input.note,
        'paymentMethod': input.paymentMethod,
      },
    );

    return (await _expenseDao.getExpenseWithCategory(existing.id))!;
  }

  Future<void> voidExpense({
    required int id,
    required String reason,
  }) async {
    _enforceManageAccess();

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AppException('Alasan pembatalan (void) pengeluaran wajib diisi.');
    }

    final existing = await _expenseDao.getExpenseById(id);
    if (existing == null) {
      throw const AppException('Data pengeluaran tidak ditemukan.');
    }

    if (existing.status == 'void') {
      throw const AppException('Pengeluaran ini sudah berstatus void.');
    }

    final currentUserId = Get.isRegistered<AuthService>()
        ? (AuthService.to.currentUser.value?.id ?? 1)
        : 1;

    await _expenseDao.voidExpense(
      id: id,
      reason: trimmedReason,
      voidedBy: currentUserId,
    );

    final category = await _expenseDao.getCategoryById(existing.categoryId);

    // Audit log void
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    await audit?.log(
      action: AuditActions.expenseVoid,
      entity: 'expenses',
      entityId: id,
      detail: {
        'amount': existing.amount,
        'category': category?.name ?? 'Operasional',
        'reason': trimmedReason,
      },
    );
  }

  Future<List<ExpenseWithCategory>> getExpensesPage({
    DateTime? startDate,
    DateTime? endDate,
    int? categoryId,
    String? status,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    _enforceViewAccess();
    return _expenseDao.getExpensesPage(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
      status: status,
      searchQuery: searchQuery,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getTotalExpensesForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    _enforceViewAccess();
    return _expenseDao.getTotalExpensesForRange(from: from, to: to);
  }

  Future<List<ExpenseCategoryAggregate>> getExpenseCategoryBreakdown({
    required DateTime from,
    required DateTime to,
  }) async {
    _enforceViewAccess();
    return _expenseDao.getExpenseCategoryBreakdown(from: from, to: to);
  }
}

