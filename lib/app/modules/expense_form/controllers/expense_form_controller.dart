import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/expense_repository.dart';

class ExpenseFormController extends GetxController {
  final ExpenseRepository _expenseRepo = Get.find<ExpenseRepository>();

  final formKey = GlobalKey<FormState>();

  final selectedDate = DateTime.now().obs;
  final selectedCategoryId = Rxn<int>();
  final selectedPaymentMethod = 'cash'.obs;

  final amountController = TextEditingController();
  final noteController = TextEditingController();

  final categories = <ExpenseCategory>[].obs;
  final isLoadingCategories = true.obs;
  final isSaving = false.obs;

  Expense? existingExpense;
  bool get isEditMode => existingExpense != null;

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments is Expense) {
      existingExpense = Get.arguments as Expense;
      selectedDate.value = existingExpense!.date;
      selectedCategoryId.value = existingExpense!.categoryId;
      selectedPaymentMethod.value = existingExpense!.paymentMethod;
      amountController.text = existingExpense!.amount.toString();
      noteController.text = existingExpense!.note ?? '';
    }
    loadCategories();
  }

  @override
  void onClose() {
    amountController.dispose();
    noteController.dispose();
    super.onClose();
  }

  Future<void> loadCategories() async {
    isLoadingCategories.value = true;
    try {
      final list = await _expenseRepo.getActiveCategories();
      categories.assignAll(list);
      if (selectedCategoryId.value == null && list.isNotEmpty) {
        selectedCategoryId.value = list.first.id;
      }
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat kategori: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingCategories.value = false;
    }
  }

  Future<void> pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate.value,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      // Pertahankan jam/menit saat ini
      final now = DateTime.now();
      selectedDate.value = DateTime(
        picked.year,
        picked.month,
        picked.day,
        now.hour,
        now.minute,
      );
    }
  }

  Future<void> quickAddCategory(String name) async {
    try {
      final cat = await _expenseRepo.createCategory(name);
      await loadCategories();
      selectedCategoryId.value = cat.id;
      Get.snackbar('Berhasil', 'Kategori "${cat.name}" ditambahkan.',
          backgroundColor: Colors.green.shade800, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Gagal', e is AppException ? e.message : e.toString(),
          backgroundColor: Colors.red.shade800, colorText: Colors.white);
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    if (selectedCategoryId.value == null) {
      Get.snackbar('Perhatian', 'Silakan pilih kategori pengeluaran.',
          backgroundColor: Colors.orange.shade800, colorText: Colors.white);
      return;
    }

    final rawAmountStr = amountController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(rawAmountStr) ?? 0;

    if (amount <= 0) {
      Get.snackbar('Perhatian', 'Nominal pengeluaran harus lebih besar dari 0.',
          backgroundColor: Colors.orange.shade800, colorText: Colors.white);
      return;
    }

    isSaving.value = true;
    try {
      if (isEditMode) {
        await _expenseRepo.updateExpense(
          UpdateExpenseInput(
            id: existingExpense!.id,
            date: selectedDate.value,
            categoryId: selectedCategoryId.value!,
            amount: amount,
            note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
            paymentMethod: selectedPaymentMethod.value,
          ),
        );
        Get.back(result: true);
        Get.snackbar(
          'Sukses',
          'Pengeluaran berhasil diperbarui.',
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
        );
      } else {
        await _expenseRepo.createExpense(
          CreateExpenseInput(
            date: selectedDate.value,
            categoryId: selectedCategoryId.value!,
            amount: amount,
            note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
            paymentMethod: selectedPaymentMethod.value,
          ),
        );
        Get.back(result: true);
        Get.snackbar(
          'Sukses',
          'Pengeluaran berhasil dicatat.',
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Gagal Menyimpan',
        e is AppException ? e.message : e.toString(),
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
      );
    } finally {
      isSaving.value = false;
    }
  }
}
