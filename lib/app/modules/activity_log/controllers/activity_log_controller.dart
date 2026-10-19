import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/user_repository.dart';

class ActivityLogController extends GetxController {
  final AuditRepository _auditRepo = Get.find<AuditRepository>();
  final UserRepository _userRepo = Get.find<UserRepository>();

  final logs = <AuditEntry>[].obs;
  final users = <User>[].obs;

  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  // Filter & Pencarian
  final selectedDateFilter = 'all'.obs; // 'all' | 'today' | 'yesterday' | '7days' | 'month' | 'custom'
  final customDateRange = Rx<DateTimeRange?>(null);
  final selectedUserId = Rxn<int>();
  final selectedCategory = 'Semua'.obs; // 'Semua', 'Produk', 'Stok', 'Penjualan', 'Akun', 'Pengaturan', 'Sistem'
  final searchQuery = ''.obs;
  final searchController = TextEditingController();

  final scrollController = ScrollController();
  static const int pageSize = 30;
  int _currentOffset = 0;

  bool get canViewAudit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.auditView);
  }

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _loadUsers();
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

  Future<void> _loadUsers() async {
    try {
      final list = await _userRepo.getAllUsers();
      users.assignAll(list);
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
    if (!canViewAudit) {
      isLoading.value = false;
      return;
    }

    isLoading.value = true;
    _currentOffset = 0;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final page = await _auditRepo.getLogsPage(
        limit: pageSize,
        offset: 0,
        startDate: startDate,
        endDate: endDate,
        userId: selectedUserId.value,
        category: selectedCategory.value == 'Semua' ? null : selectedCategory.value,
        searchQuery: searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim(),
      );

      logs.assignAll(page);
      _currentOffset = page.length;
      hasMore.value = page.length >= pageSize;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat riwayat aktivitas: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;

    isLoadingMore.value = true;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final next = await _auditRepo.getLogsPage(
        limit: pageSize,
        offset: _currentOffset,
        startDate: startDate,
        endDate: endDate,
        userId: selectedUserId.value,
        category: selectedCategory.value == 'Semua' ? null : selectedCategory.value,
        searchQuery: searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim(),
      );

      logs.addAll(next);
      _currentOffset += next.length;
      hasMore.value = next.length >= pageSize;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat log berikutnya: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingMore.value = false;
    }
  }

  void setDateFilter(String filter, {DateTimeRange? customRange}) {
    selectedDateFilter.value = filter;
    if (customRange != null) {
      customDateRange.value = customRange;
    }
    loadInitialData();
  }

  void setUserFilter(int? userId) {
    selectedUserId.value = userId;
    loadInitialData();
  }

  void setCategoryFilter(String category) {
    selectedCategory.value = category;
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
    selectedDateFilter.value = 'all';
    customDateRange.value = null;
    selectedUserId.value = null;
    selectedCategory.value = 'Semua';
    searchController.clear();
    searchQuery.value = '';
    loadInitialData();
  }

  Map<String, List<AuditEntry>> get groupedLogs {
    final map = <String, List<AuditEntry>>{};
    for (final log in logs) {
      final local = log.createdAt.toLocal();
      final dayKey = DateFormat('yyyy-MM-dd').format(local);
      map.putIfAbsent(dayKey, () => []).add(log);
    }
    return map;
  }
}
