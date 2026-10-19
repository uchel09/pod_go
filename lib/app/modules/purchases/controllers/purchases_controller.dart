import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/purchase_dao.dart';
import '../../../data/repositories/purchase_repository.dart';
import '../../../data/repositories/supplier_repository.dart';

enum PurchaseDateFilter {
  today,
  yesterday,
  last7Days,
  thisMonth,
  custom,
  all,
}

class PurchasesController extends GetxController {
  final PurchaseRepository _purchaseRepo = Get.find<PurchaseRepository>();
  final SupplierRepository _supplierRepo = Get.find<SupplierRepository>();

  final purchases = <PurchaseWithSupplier>[].obs;
  final suppliers = <Supplier>[].obs;

  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  // Filter State
  final selectedDateFilter = PurchaseDateFilter.all.obs;
  final customStartDate = Rxn<DateTime>();
  final customEndDate = Rxn<DateTime>();
  final selectedSupplierId = Rxn<int>();
  final selectedStatus = 'all'.obs; // 'all' | 'received' | 'cancelled'
  final searchQuery = ''.obs;

  final searchController = TextEditingController();
  final int pageSize = 20;
  int _currentOffset = 0;

  StreamSubscription? _purchasesSub;

  bool get canPurchase => PermissionService.to.can(PermissionKeys.stockPurchase);

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
    loadPurchases(refresh: true);
  }

  @override
  void onClose() {
    _purchasesSub?.cancel();
    searchController.dispose();
    super.onClose();
  }

  Future<void> loadSuppliers() async {
    try {
      suppliers.value = await _supplierRepo.getAllSuppliers();
    } catch (_) {}
  }

  DateTime? get effectiveStartDate {
    final now = DateTime.now();
    switch (selectedDateFilter.value) {
      case PurchaseDateFilter.today:
        return DateTime(now.year, now.month, now.day);
      case PurchaseDateFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTime(y.year, y.month, y.day);
      case PurchaseDateFilter.last7Days:
        final d = now.subtract(const Duration(days: 7));
        return DateTime(d.year, d.month, d.day);
      case PurchaseDateFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case PurchaseDateFilter.custom:
        return customStartDate.value;
      case PurchaseDateFilter.all:
        return null;
    }
  }

  DateTime? get effectiveEndDate {
    final now = DateTime.now();
    switch (selectedDateFilter.value) {
      case PurchaseDateFilter.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case PurchaseDateFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTime(y.year, y.month, y.day, 23, 59, 59, 999);
      case PurchaseDateFilter.last7Days:
      case PurchaseDateFilter.thisMonth:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case PurchaseDateFilter.custom:
        if (customEndDate.value == null) return null;
        final d = customEndDate.value!;
        return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
      case PurchaseDateFilter.all:
        return null;
    }
  }

  Future<void> loadPurchases({bool refresh = false}) async {
    if (refresh) {
      isLoading.value = true;
      _currentOffset = 0;
      hasMore.value = true;
    }

    try {
      final results = await _purchaseRepo.getPurchasesPage(
        limit: pageSize,
        offset: _currentOffset,
        startDate: effectiveStartDate,
        endDate: effectiveEndDate,
        supplierId: selectedSupplierId.value,
        status: selectedStatus.value == 'all' ? null : selectedStatus.value,
        searchQuery: searchQuery.value,
      );

      if (refresh) {
        purchases.value = results;
      } else {
        purchases.addAll(results);
      }

      if (results.length < pageSize) {
        hasMore.value = false;
      }
      _currentOffset += results.length;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat daftar pembelian: $e');
    } finally {
      isLoading.value = false;
      isLoadingMore.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    await loadPurchases(refresh: false);
  }

  void setDateFilter(PurchaseDateFilter filter, {DateTime? start, DateTime? end}) {
    selectedDateFilter.value = filter;
    if (filter == PurchaseDateFilter.custom) {
      customStartDate.value = start;
      customEndDate.value = end;
    }
    loadPurchases(refresh: true);
  }

  void setSupplierFilter(int? supplierId) {
    selectedSupplierId.value = supplierId;
    loadPurchases(refresh: true);
  }

  void setStatusFilter(String status) {
    selectedStatus.value = status;
    loadPurchases(refresh: true);
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    loadPurchases(refresh: true);
  }

  // Pengelompokan data per hari berdasarkan tanggal lokal
  Map<String, List<PurchaseWithSupplier>> get groupedPurchases {
    final map = <String, List<PurchaseWithSupplier>>{};
    for (final item in purchases) {
      final key = DateFormat('yyyy-MM-dd').format(item.purchase.date.toLocal());
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  int get totalCompletedCount =>
      purchases.where((p) => p.purchase.status == 'received').length;

  int get totalCompletedAmount => purchases
      .where((p) => p.purchase.status == 'received')
      .fold<int>(0, (sum, p) => sum + p.purchase.total);

  Future<PurchaseDetailEntry?> getPurchaseDetail(int purchaseId) =>
      _purchaseRepo.getPurchaseDetail(purchaseId);

  Future<bool> cancelPurchase({
    required int purchaseId,
    required String reason,
  }) async {
    try {
      await _purchaseRepo.cancelPurchase(
        purchaseId: purchaseId,
        reason: reason,
      );
      await loadPurchases(refresh: true);
      Get.snackbar(
        'Pembelian Dibatalkan',
        'Transaksi berhasil dibatalkan dan stok produk telah dikembalikan.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } on AppException catch (e) {
      e.showSnackbar();
      return false;
    } catch (e) {
      Get.snackbar('Error', 'Gagal membatalkan pembelian: $e');
      return false;
    }
  }
}
