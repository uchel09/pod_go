import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/stock_dao.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../data/repositories/stock_repository.dart';

class StockCardController extends GetxController {
  final StockRepository _stockRepo = Get.find<StockRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final SaleRepository _saleRepo = Get.find<SaleRepository>();

  final entries = <StockCardEntry>[].obs;
  final products = <Product>[].obs;

  final selectedProductId = Rxn<int>();
  final selectedProduct = Rxn<Product>();
  final selectedType = 'all'.obs; // 'all' | 'sale' | 'purchase' | 'opname' | 'void' | 'adjustment'
  final selectedDateFilter = 'all'.obs; // 'all' | 'today' | 'yesterday' | '7days' | 'month' | 'custom'
  final customDateRange = Rx<DateTimeRange?>(null);

  final searchQuery = ''.obs;
  final searchController = TextEditingController();
  final scrollController = ScrollController();

  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  static const int pageSize = 30;
  int _currentOffset = 0;

  bool get canViewStock {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.stockView);
  }

  bool get isPerProductMode => selectedProductId.value != null;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);

    // Cek arguments jika diarahkan langsung dari produk tertentu
    if (Get.arguments is Map && Get.arguments['productId'] != null) {
      selectedProductId.value = Get.arguments['productId'] as int;
    }

    _loadProducts();
    loadInitialData();
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
      if (!isLoadingMore.value && hasMore.value) {
        loadMore();
      }
    }
  }

  Future<void> _loadProducts() async {
    try {
      final list = await _productRepo.getAllProducts();
      products.assignAll(list);
      if (selectedProductId.value != null) {
        selectedProduct.value = products.firstWhereOrNull((p) => p.id == selectedProductId.value);
      }
    } catch (_) {}
  }

  (DateTime? start, DateTime? end) getActiveDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (selectedDateFilter.value) {
      case 'today':
        return (today, today.add(const Duration(days: 1)));
      case 'yesterday':
        return (today.subtract(const Duration(days: 1)), today);
      case '7days':
        return (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1)));
      case 'month':
        final monthStart = DateTime(now.year, now.month, 1);
        final nextMonth = (now.month == 12)
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return (monthStart, nextMonth);
      case 'custom':
        final range = customDateRange.value;
        if (range != null) {
          final start = DateTime(range.start.year, range.start.month, range.start.day);
          final end = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
          return (start, end);
        }
        return (null, null);
      case 'all':
      default:
        return (null, null);
    }
  }

  Future<void> loadInitialData() async {
    if (!canViewStock) {
      isLoading.value = false;
      return;
    }

    isLoading.value = true;
    _currentOffset = 0;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final page = await _stockRepo.getStockCardPage(
        limit: pageSize,
        offset: 0,
        productId: selectedProductId.value,
        type: selectedType.value == 'all' ? null : selectedType.value,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim(),
      );

      entries.assignAll(page);
      _currentOffset = page.length;
      hasMore.value = page.length >= pageSize;

      if (selectedProductId.value != null) {
        selectedProduct.value = await _productRepo.getProductById(selectedProductId.value!);
      } else {
        selectedProduct.value = null;
      }
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat kartu stok: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;

    isLoadingMore.value = true;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final next = await _stockRepo.getStockCardPage(
        limit: pageSize,
        offset: _currentOffset,
        productId: selectedProductId.value,
        type: selectedType.value == 'all' ? null : selectedType.value,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim(),
      );

      entries.addAll(next);
      _currentOffset += next.length;
      hasMore.value = next.length >= pageSize;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat halaman mutasi berikutnya: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingMore.value = false;
    }
  }

  void setProductFilter(int? productId) {
    selectedProductId.value = productId;
    loadInitialData();
  }

  void setTypeFilter(String type) {
    selectedType.value = type;
    loadInitialData();
  }

  void setDateFilter(String filter, {DateTimeRange? customRange}) {
    selectedDateFilter.value = filter;
    if (customRange != null) {
      customDateRange.value = customRange;
    }
    loadInitialData();
  }

  void onSearchSubmitted(String query) {
    searchQuery.value = query;
    loadInitialData();
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
    loadInitialData();
  }

  void clearAllFilters() {
    selectedProductId.value = null;
    selectedType.value = 'all';
    selectedDateFilter.value = 'all';
    customDateRange.value = null;
    searchController.clear();
    searchQuery.value = '';
    loadInitialData();
  }

  Future<SaleDetail?> getSaleDetail(int saleId) => _saleRepo.getSaleDetail(saleId);
}
