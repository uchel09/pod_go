import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/daos/customer_dao.dart';
import '../../../data/repositories/customer_repository.dart';

class CustomersController extends GetxController {
  final CustomerRepository _customerRepo = Get.find<CustomerRepository>();

  final customers = <CustomerWithBalance>[].obs;
  final totalReceivables = 0.obs;
  final isLoading = true.obs;

  final searchQuery = ''.obs;
  final onlyWithDebt = false.obs;

  final searchController = TextEditingController();
  Timer? _debounceTimer;

  bool get canManage => PermissionService.to.can(PermissionKeys.customerManage);
  bool get canView => PermissionService.to.can(PermissionKeys.customerView);
  bool get hasCustomerFeature => FeatureGate.to.isEnabled(Feature.customerCredit);

  @override
  void onInit() {
    super.onInit();
    if (hasCustomerFeature && canView) {
      loadInitialData();
    } else {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    searchController.dispose();
    super.onClose();
  }

  void onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      searchQuery.value = value.trim();
      fetchCustomers();
    });
  }

  Future<void> loadInitialData() async {
    isLoading.value = true;
    try {
      await Future.wait([
        fetchCustomers(showLoading: false),
        fetchTotalReceivables(),
      ]);
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat data pelanggan: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchCustomers({bool showLoading = true}) async {
    if (showLoading) isLoading.value = true;
    try {
      final list = await _customerRepo.getCustomers(
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
        onlyWithDebt: onlyWithDebt.value,
      );
      customers.assignAll(list);
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat daftar pelanggan: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (showLoading) isLoading.value = false;
    }
  }

  Future<void> fetchTotalReceivables() async {
    try {
      final total = await _customerRepo.getTotalReceivables();
      totalReceivables.value = total;
    } catch (_) {}
  }

  void toggleOnlyWithDebt() {
    onlyWithDebt.value = !onlyWithDebt.value;
    fetchCustomers();
  }

  Future<CustomerWithBalance?> createCustomer(CreateCustomerInput input) async {
    try {
      final created = await _customerRepo.createCustomer(input);
      await loadInitialData();
      Get.snackbar('Sukses', 'Pelanggan ${created.customer.name} berhasil ditambahkan.',
          snackPosition: SnackPosition.BOTTOM);
      return created;
    } on AppException catch (e) {
      Get.snackbar('Gagal', e.message, snackPosition: SnackPosition.BOTTOM);
      return null;
    } catch (e) {
      Get.snackbar('Gagal', 'Terjadi kesalahan: $e', snackPosition: SnackPosition.BOTTOM);
      return null;
    }
  }
}
