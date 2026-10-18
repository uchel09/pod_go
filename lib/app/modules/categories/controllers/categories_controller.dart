import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Value;

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/product_repository.dart';

class CategoriesController extends GetxController {
  final CategoryRepository _categoryRepo = Get.find<CategoryRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final allCategories = <Category>[].obs;
  final searchQuery = ''.obs;
  final isLoading = true.obs;
  final searchController = TextEditingController();

  bool get canEdit => PermissionService.to.can(PermissionKeys.productEdit);
  bool get canView => PermissionService.to.can(PermissionKeys.productView);

  @override
  void onInit() {
    super.onInit();
    _bindCategoriesStream();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  void _bindCategoriesStream() {
    allCategories.bindStream(
      _categoryRepo.watchAllCategories().map((list) {
        isLoading.value = false;
        return list;
      }),
    );
  }

  /// Daftar kategori yang disaring berdasarkan kata kunci pencarian
  List<Category> get filteredCategories {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return allCategories;
    return allCategories.where((c) => c.name.toLowerCase().contains(query)).toList();
  }

  void updateSearch(String query) {
    searchQuery.value = query;
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }

  /// Menambah kategori baru
  Future<void> addCategory(String rawName) async {
    final name = rawName.trim();
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengedit kategori produk.');
    }

    if (name.isEmpty) {
      throw const AppException('Nama kategori wajib diisi.');
    }

    final exists = allCategories.any((c) => c.name.trim().toLowerCase() == name.toLowerCase());
    if (exists) {
      throw AppException('Kategori "$name" sudah ada. Gunakan nama lain.');
    }

    final id = await _categoryRepo.insertCategory(
      CategoriesCompanion(
        name: Value(name),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'category.create',
        entity: 'categories',
        entityId: id,
        detail: {'name': name},
      );
    }
  }

  /// Mengubah nama kategori yang sudah ada
  Future<void> updateCategory(int id, String rawNewName) async {
    final newName = rawNewName.trim();
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengedit kategori produk.');
    }

    if (newName.isEmpty) {
      throw const AppException('Nama kategori wajib diisi.');
    }

    final exists = allCategories.any(
      (c) => c.id != id && c.name.trim().toLowerCase() == newName.toLowerCase(),
    );
    if (exists) {
      throw AppException('Kategori "$newName" sudah ada. Gunakan nama lain.');
    }

    await _categoryRepo.updateCategory(
      CategoriesCompanion(
        id: Value(id),
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'category.update',
        entity: 'categories',
        entityId: id,
        detail: {'name': newName},
      );
    }
  }

  /// Menghapus kategori, ditolak jika masih digunakan oleh produk
  Future<void> deleteCategory(Category category) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin menghapus kategori produk.');
    }

    // Periksa apakah kategori masih digunakan oleh produk aktif
    final productCount = await _productRepo.countProductsByCategoryId(category.id);
    if (productCount > 0) {
      throw AppException(
        'Kategori "${category.name}" tidak dapat dihapus karena masih digunakan oleh $productCount produk.\n\nSilakan pindahkan kategori produk terkait terlebih dahulu.',
        code: 'CATEGORY_IN_USE',
      );
    }

    await _categoryRepo.deleteCategory(category.id);

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'category.delete',
        entity: 'categories',
        entityId: category.id,
        detail: {'name': category.name},
      );
    }
  }

  /// Dialog form tambah kategori
  void showAddCategoryDialog(BuildContext context) {
    if (!canEdit) return;

    final textController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Tambah Kategori'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
            hintText: 'Misal: Makanan, Minuman, Snack',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await addCategory(textController.text);
                Get.back();
                Get.snackbar(
                  'Sukses',
                  'Kategori berhasil ditambahkan',
                  snackPosition: SnackPosition.BOTTOM,
                );
              } on AppException catch (e) {
                e.showSnackbar();
              } catch (e) {
                Get.snackbar('Error', 'Gagal menambahkan kategori: $e');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Dialog form edit kategori
  void showEditCategoryDialog(BuildContext context, Category category) {
    if (!canEdit) return;

    final textController = TextEditingController(text: category.name);
    Get.dialog(
      AlertDialog(
        title: const Text('Edit Kategori'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await updateCategory(category.id, textController.text);
                Get.back();
                Get.snackbar(
                  'Sukses',
                  'Kategori berhasil diperbarui',
                  snackPosition: SnackPosition.BOTTOM,
                );
              } on AppException catch (e) {
                e.showSnackbar();
              } catch (e) {
                Get.snackbar('Error', 'Gagal memperbarui kategori: $e');
              }
            },
            child: const Text('Perbarui'),
          ),
        ],
      ),
    );
  }

  /// Dialog konfirmasi hapus kategori
  void confirmDeleteCategory(BuildContext context, Category category) async {
    if (!canEdit) return;

    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Hapus Kategori',
      message: 'Apakah Anda yakin ingin menghapus kategori "${category.name}"?',
      confirmText: 'Hapus',
      isDestructive: true,
    );

    if (!confirmed) return;

    try {
      await deleteCategory(category);
      Get.snackbar(
        'Sukses',
        'Kategori "${category.name}" berhasil dihapus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      e.showSnackbar();
    } catch (e) {
      Get.snackbar('Error', 'Gagal menghapus kategori: $e');
    }
  }
}
