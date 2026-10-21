import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/expense_dao.dart';
import '../../../data/repositories/expense_repository.dart';

class ExpensesController extends GetxController {
  final ExpenseRepository _expenseRepo = Get.find<ExpenseRepository>();

  final expenses = <ExpenseWithCategory>[].obs;
  final categories = <ExpenseCategory>[].obs;
  final totalExpensesPeriod = 0.obs;

  final isLoading = true.obs;
  final isVoiding = false.obs;

  // Filters
  final selectedDateFilter = 'thisMonth'.obs; // 'all' | 'today' | 'yesterday' | '7days' | 'thisMonth' | 'custom'
  final customDateRange = Rx<DateTimeRange?>(null);
  final selectedCategoryId = Rxn<int>();
  final selectedStatus = 'all'.obs; // 'all' | 'active' | 'void'
  final searchQuery = ''.obs;

  final searchController = TextEditingController();

  bool get canManage => PermissionService.to.can(PermissionKeys.expenseManage);
  bool get canView => PermissionService.to.can(PermissionKeys.expenseView);
  bool get hasExpensesFeature => FeatureGate.to.isEnabled(Feature.expenses);

  @override
  void onInit() {
    super.onInit();
    if (hasExpensesFeature && canView) {
      loadInitialData();
    } else {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> loadInitialData() async {
    isLoading.value = true;
    try {
      await fetchCategories();
      await fetchExpenses();
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat data pengeluaran: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchCategories() async {
    try {
      final list = await _expenseRepo.getAllCategories();
      categories.assignAll(list);
    } catch (_) {}
  }

  (DateTime?, DateTime?) getActiveDateRange() {
    final now = DateTime.now();
    switch (selectedDateFilter.value) {
      case 'today':
        final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (start, end);
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        final start = DateTime(y.year, y.month, y.day, 0, 0, 0);
        final end = DateTime(y.year, y.month, y.day, 23, 59, 59);
        return (start, end);
      case '7days':
        final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (start, end);
      case 'thisMonth':
        final start = DateTime(now.year, now.month, 1, 0, 0, 0);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return (start, end);
      case 'custom':
        if (customDateRange.value != null) {
          final s = customDateRange.value!.start;
          final e = customDateRange.value!.end;
          return (
            DateTime(s.year, s.month, s.day, 0, 0, 0),
            DateTime(e.year, e.month, e.day, 23, 59, 59),
          );
        }
        return (null, null);
      case 'all':
      default:
        return (null, null);
    }
  }

  Future<void> fetchExpenses() async {
    isLoading.value = true;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final query = searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim();

      final list = await _expenseRepo.getExpensesPage(
        startDate: startDate,
        endDate: endDate,
        categoryId: selectedCategoryId.value,
        status: selectedStatus.value == 'all' ? null : selectedStatus.value,
        searchQuery: query,
        limit: 1000,
      );

      expenses.assignAll(list);

      // Hitung total pengeluaran aktif dalam rentang
      final activeSum = list
          .where((e) => e.status == 'active')
          .fold<int>(0, (sum, item) => sum + item.amount);
      totalExpensesPeriod.value = activeSum;
    } catch (e) {
      Get.snackbar('Error', 'Gagal mengambil data pengeluaran: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  void setDateFilter(String filter) {
    selectedDateFilter.value = filter;
    if (filter != 'custom') {
      customDateRange.value = null;
      fetchExpenses();
    }
  }

  Future<void> pickCustomDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: customDateRange.value ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
    );

    if (picked != null) {
      customDateRange.value = picked;
      selectedDateFilter.value = 'custom';
      fetchExpenses();
    }
  }

  void setCategoryFilter(int? categoryId) {
    selectedCategoryId.value = categoryId;
    fetchExpenses();
  }

  void setStatusFilter(String status) {
    selectedStatus.value = status;
    fetchExpenses();
  }

  void setSearchQuery(String query) {
    searchQuery.value = query;
    fetchExpenses();
  }

  Future<void> handleVoidExpense(BuildContext context, ExpenseWithCategory item) async {
    if (!canManage) {
      Get.snackbar('Akses Ditolak', 'Anda tidak memiliki izin membatalkan pengeluaran.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Batalkan (Void) Pengeluaran'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Anda akan membatalkan pengeluaran "${item.categoryName}" sebesar Rp ${item.amount}.\n'
                'Data ini tidak akan dihapus, melainkan ditandai sebagai Batal (Void) dan tidak lagi dihitung di laporan keuangan.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Alasan Pembatalan *',
                  hintText: 'Contoh: Salah input nominal',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Alasan pembatalan wajib diisi';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tutup'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Ya, Batalkan (Void)'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      isVoiding.value = true;
      try {
        await _expenseRepo.voidExpense(
          id: item.id,
          reason: reasonController.text.trim(),
        );
        Get.snackbar(
          'Berhasil',
          'Pengeluaran berhasil dibatalkan (void).',
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
        );
        fetchExpenses();
      } catch (e) {
        Get.snackbar(
          'Gagal Membatalkan',
          e is AppException ? e.message : e.toString(),
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
        );
      } finally {
        isVoiding.value = false;
      }
    }
  }

  // --- KELOLA KATEGORI ---

  Future<void> addCategory(String name) async {
    try {
      await _expenseRepo.createCategory(name);
      await fetchCategories();
      Get.snackbar('Sukses', 'Kategori "$name" berhasil ditambahkan.',
          backgroundColor: Colors.green.shade800, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Gagal', e is AppException ? e.message : e.toString(),
          backgroundColor: Colors.red.shade800, colorText: Colors.white);
    }
  }

  Future<void> updateCategory(int id, String name, bool isActive) async {
    try {
      await _expenseRepo.updateCategory(id, name: name, isActive: isActive);
      await fetchCategories();
      Get.snackbar('Sukses', 'Kategori berhasil diperbarui.',
          backgroundColor: Colors.green.shade800, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Gagal', e is AppException ? e.message : e.toString(),
          backgroundColor: Colors.red.shade800, colorText: Colors.white);
    }
  }

  Future<void> deleteCategory(int id, String name) async {
    try {
      await _expenseRepo.deleteCategory(id);
      await fetchCategories();
      Get.snackbar('Sukses', 'Kategori "$name" berhasil dihapus.',
          backgroundColor: Colors.green.shade800, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Tidak Dapat Dihapus', e is AppException ? e.message : e.toString(),
          backgroundColor: Colors.red.shade800, colorText: Colors.white, duration: const Duration(seconds: 4));
    }
  }
}
