import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Value;

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/unit_repository.dart';

class UnitsController extends GetxController {
  final UnitRepository _unitRepo = Get.find<UnitRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final allUnits = <Unit>[].obs;
  final searchQuery = ''.obs;
  final isLoading = true.obs;
  final searchController = TextEditingController();

  bool get canEdit => PermissionService.to.can(PermissionKeys.productEdit);
  bool get canView => PermissionService.to.can(PermissionKeys.productView);

  @override
  void onInit() {
    super.onInit();
    _bindUnitsStream();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  void _bindUnitsStream() {
    allUnits.bindStream(
      _unitRepo.watchAllUnits().map((list) {
        isLoading.value = false;
        return list;
      }),
    );
  }

  /// Daftar satuan yang disaring berdasarkan kata kunci pencarian
  List<Unit> get filteredUnits {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return allUnits;
    return allUnits.where((u) {
      return u.name.toLowerCase().contains(query) ||
          u.symbol.toLowerCase().contains(query);
    }).toList();
  }

  void updateSearch(String query) {
    searchQuery.value = query;
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }

  /// Menambah satuan baru
  Future<void> addUnit(String rawName, String rawSymbol) async {
    final name = rawName.trim();
    final symbol = rawSymbol.trim();

    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengedit satuan produk.');
    }

    if (name.isEmpty) {
      throw const AppException('Nama satuan wajib diisi.');
    }

    if (symbol.isEmpty) {
      throw const AppException('Simbol satuan wajib diisi.');
    }

    final nameExists = allUnits.any((u) => u.name.trim().toLowerCase() == name.toLowerCase());
    if (nameExists) {
      throw AppException('Nama satuan "$name" sudah digunakan. Gunakan nama lain.');
    }

    final symbolExists = allUnits.any((u) => u.symbol.trim().toLowerCase() == symbol.toLowerCase());
    if (symbolExists) {
      throw AppException('Simbol satuan "$symbol" sudah digunakan. Gunakan simbol lain.');
    }

    final id = await _unitRepo.insertUnit(
      UnitsCompanion(
        name: Value(name),
        symbol: Value(symbol),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'unit.create',
        entity: 'units',
        entityId: id,
        detail: {'name': name, 'symbol': symbol},
      );
    }
  }

  /// Mengubah data satuan yang sudah ada
  Future<void> updateUnit(int id, String rawNewName, String rawNewSymbol) async {
    final newName = rawNewName.trim();
    final newSymbol = rawNewSymbol.trim();

    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin mengedit satuan produk.');
    }

    if (newName.isEmpty) {
      throw const AppException('Nama satuan wajib diisi.');
    }

    if (newSymbol.isEmpty) {
      throw const AppException('Simbol satuan wajib diisi.');
    }

    final nameExists = allUnits.any(
      (u) => u.id != id && u.name.trim().toLowerCase() == newName.toLowerCase(),
    );
    if (nameExists) {
      throw AppException('Nama satuan "$newName" sudah digunakan. Gunakan nama lain.');
    }

    final symbolExists = allUnits.any(
      (u) => u.id != id && u.symbol.trim().toLowerCase() == newSymbol.toLowerCase(),
    );
    if (symbolExists) {
      throw AppException('Simbol satuan "$newSymbol" sudah digunakan. Gunakan simbol lain.');
    }

    await _unitRepo.updateUnit(
      UnitsCompanion(
        id: Value(id),
        name: Value(newName),
        symbol: Value(newSymbol),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'unit.update',
        entity: 'units',
        entityId: id,
        detail: {'name': newName, 'symbol': newSymbol},
      );
    }
  }

  /// Menghapus satuan, ditolak jika masih digunakan oleh produk
  Future<void> deleteUnit(Unit unit) async {
    if (!canEdit) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin menghapus satuan produk.');
    }

    // Periksa apakah satuan masih digunakan oleh produk aktif
    final productCount = await _productRepo.countProductsByUnitId(unit.id);
    if (productCount > 0) {
      throw AppException(
        'Satuan "${unit.name} (${unit.symbol})" tidak dapat dihapus karena masih digunakan oleh $productCount produk.\n\nSilakan ubah satuan produk terkait terlebih dahulu.',
        code: 'UNIT_IN_USE',
      );
    }

    await _unitRepo.deleteUnit(unit.id);

    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'unit.delete',
        entity: 'units',
        entityId: unit.id,
        detail: {'name': unit.name, 'symbol': unit.symbol},
      );
    }
  }

  /// Dialog form tambah satuan
  void showAddUnitDialog(BuildContext context) {
    if (!canEdit) return;

    final nameController = TextEditingController();
    final symbolController = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('Tambah Satuan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Satuan *',
                hintText: 'Misal: Pieces, Kilogram, Dus',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: symbolController,
              decoration: const InputDecoration(
                labelText: 'Simbol / Singkatan *',
                hintText: 'Misal: pcs, kg, dus, ltr',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await addUnit(nameController.text, symbolController.text);
                Get.back();
                Get.snackbar(
                  'Sukses',
                  'Satuan berhasil ditambahkan',
                  snackPosition: SnackPosition.BOTTOM,
                );
              } on AppException catch (e) {
                e.showSnackbar();
              } catch (e) {
                Get.snackbar('Error', 'Gagal menambahkan satuan: $e');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Dialog form edit satuan
  void showEditUnitDialog(BuildContext context, Unit unit) {
    if (!canEdit) return;

    final nameController = TextEditingController(text: unit.name);
    final symbolController = TextEditingController(text: unit.symbol);

    Get.dialog(
      AlertDialog(
        title: const Text('Edit Satuan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Satuan *',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: symbolController,
              decoration: const InputDecoration(
                labelText: 'Simbol / Singkatan *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await updateUnit(unit.id, nameController.text, symbolController.text);
                Get.back();
                Get.snackbar(
                  'Sukses',
                  'Satuan berhasil diperbarui',
                  snackPosition: SnackPosition.BOTTOM,
                );
              } on AppException catch (e) {
                e.showSnackbar();
              } catch (e) {
                Get.snackbar('Error', 'Gagal memperbarui satuan: $e');
              }
            },
            child: const Text('Perbarui'),
          ),
        ],
      ),
    );
  }

  /// Dialog konfirmasi hapus satuan
  void confirmDeleteUnit(BuildContext context, Unit unit) async {
    if (!canEdit) return;

    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Hapus Satuan',
      message: 'Apakah Anda yakin ingin menghapus satuan "${unit.name} (${unit.symbol})"?',
      confirmText: 'Hapus',
      isDestructive: true,
    );

    if (!confirmed) return;

    try {
      await deleteUnit(unit);
      Get.snackbar(
        'Sukses',
        'Satuan "${unit.name}" berhasil dihapus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      e.showSnackbar();
    } catch (e) {
      Get.snackbar('Error', 'Gagal menghapus satuan: $e');
    }
  }
}
