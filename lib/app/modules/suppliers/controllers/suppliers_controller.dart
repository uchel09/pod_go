import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/supplier_repository.dart';

class SuppliersController extends GetxController {
  final SupplierRepository _supplierRepo = Get.find<SupplierRepository>();

  final suppliers = <Supplier>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  final searchController = TextEditingController();

  bool get canManage => PermissionService.to.can(PermissionKeys.stockPurchase);

  @override
  void onInit() {
    super.onInit();
    // Validasi Gate Lisensi & Hak Akses
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.purchases)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FeatureGate.to.requireFeature(Feature.purchases);
        });
        return;
      }
    }
    loadSuppliers();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> loadSuppliers() async {
    isLoading.value = true;
    try {
      if (searchQuery.value.trim().isEmpty) {
        suppliers.value = await _supplierRepo.getAllSuppliers();
      } else {
        suppliers.value = await _supplierRepo.searchSuppliers(searchQuery.value);
      }
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat data supplier: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    loadSuppliers();
  }

  Future<bool> createSupplier({
    required String name,
    String? phone,
    String? address,
  }) async {
    try {
      await _supplierRepo.createSupplier(
        name: name,
        phone: phone,
        address: address,
      );
      await loadSuppliers();
      Get.snackbar(
        'Sukses',
        'Supplier "$name" berhasil ditambahkan',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } on AppException catch (e) {
      e.showSnackbar();
      return false;
    } catch (e) {
      Get.snackbar('Error', 'Gagal menambah supplier: $e');
      return false;
    }
  }

  Future<bool> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? address,
  }) async {
    try {
      await _supplierRepo.updateSupplier(
        id: id,
        name: name,
        phone: phone,
        address: address,
      );
      await loadSuppliers();
      Get.snackbar(
        'Sukses',
        'Data supplier "$name" berhasil diperbarui',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } on AppException catch (e) {
      e.showSnackbar();
      return false;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memperbarui supplier: $e');
      return false;
    }
  }

  Future<void> deleteSupplier(Supplier supplier) async {
    try {
      await _supplierRepo.deleteSupplier(supplier.id);
      await loadSuppliers();
      Get.snackbar(
        'Terhapus',
        'Supplier "${supplier.name}" berhasil dihapus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on AppException catch (e) {
      e.showSnackbar();
    } catch (e) {
      Get.snackbar('Error', 'Gagal menghapus supplier: $e');
    }
  }
}
