import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/printing/receipt_actions.dart';
import '../../../core/printing/receipt_data.dart';
import '../../../core/printing/receipt_data_mapper.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/sale_dao.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../data/repositories/user_repository.dart';

class SalesHistoryController extends GetxController {
  final SaleRepository _saleRepo = Get.find<SaleRepository>();
  final UserRepository _userRepo = Get.find<UserRepository>();

  final entries = <SaleListEntry>[].obs;
  final dailySummaries = <String, DailySalesSummary>{}.obs;
  final aggregateSummary = Rx<DailySalesSummary?>(null);

  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;
  final isVoiding = false.obs;

  // Filter & Pencarian
  final selectedDateFilter = 'all'.obs; // 'all' | 'today' | 'yesterday' | '7days' | 'month' | 'custom'
  final customDateRange = Rx<DateTimeRange?>(null);
  final selectedStatusFilter = 'all'.obs; // 'all' | 'completed' | 'void'
  final selectedCashierId = Rxn<int>();
  final cashiers = <User>[].obs;
  final searchQuery = ''.obs;
  final searchController = TextEditingController();

  final scrollController = ScrollController();

  static const int pageSize = 30;

  bool get isSoloMode => AuthService.to.isSoloMode;

  bool get canViewAllSales {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.posViewAllSales);
  }

  String get selectedCashierName {
    final id = selectedCashierId.value;
    if (id == null) return 'Semua Kasir';
    final user = cashiers.firstWhereOrNull((u) => u.id == id);
    return user?.displayName ?? 'Kasir #$id';
  }

  bool get canViewHistory {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.posSell) ||
        PermissionService.to.can(PermissionKeys.posVoid);
  }

  bool get canVoid {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.posVoid);
  }

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
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

  /// Menghitung rentang tanggal [start, end) berdasarkan filter yang aktif.
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
    if (!canViewHistory) {
      isLoading.value = false;
      return;
    }

    // Muat daftar kasir jika belum dimuat dan memiliki izin view all
    if (cashiers.isEmpty) {
      try {
        final users = await _userRepo.getAllUsers();
        cashiers.assignAll(users);
      } catch (_) {}
    }

    isLoading.value = true;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final status = selectedStatusFilter.value;
      final query = searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim();
      final cashierId = selectedCashierId.value;

      // 1. Ringkasan agregat keseluruhan filter yang aktif (untuk total di atas list)
      final agg = await _saleRepo.getAggregateSummary(
        startDate: startDate,
        endDate: endDate,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );
      aggregateSummary.value = agg;

      // 2. Ringkasan per hari (omzet + jumlah transaksi)
      final now = DateTime.now();
      final from = startDate ?? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 180));
      final to = endDate ?? DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

      final summaries = await _saleRepo.getDailySummaries(
        from: from,
        to: to,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );
      dailySummaries.assignAll({for (final s in summaries) s.day: s});

      // 3. Muat halaman pertama transaksi
      final page = await _saleRepo.getSalesPage(
        limit: pageSize,
        startDate: startDate,
        endDate: endDate,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );
      entries.assignAll(page);
      hasMore.value = page.length >= pageSize;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat riwayat transaksi: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || entries.isEmpty) return;

    isLoadingMore.value = true;
    try {
      final (startDate, endDate) = getActiveDateRange();
      final status = selectedStatusFilter.value;
      final query = searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim();
      final cashierId = selectedCashierId.value;

      final lastSale = entries.last.sale;
      final cursor = SalesCursor.fromSale(lastSale);
      final next = await _saleRepo.getSalesPage(
        limit: pageSize,
        after: cursor,
        startDate: startDate,
        endDate: endDate,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );

      entries.addAll(next);
      hasMore.value = next.length >= pageSize;
    } catch (e) {
      Get.snackbar('Error', 'Gagal memuat halaman berikutnya: $e', snackPosition: SnackPosition.BOTTOM);
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

  void setStatusFilter(String status) {
    selectedStatusFilter.value = status;
    loadInitialData();
  }

  void setCashierFilter(int? cashierId) {
    selectedCashierId.value = cashierId;
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
    selectedStatusFilter.value = 'all';
    selectedCashierId.value = null;
    searchController.clear();
    searchQuery.value = '';
    loadInitialData();
  }

  Map<String, List<SaleListEntry>> get groupedSales {
    final map = <String, List<SaleListEntry>>{};
    for (final entry in entries) {
      final local = entry.sale.createdAt.toLocal();
      final dayKey = DateFormat('yyyy-MM-dd').format(local);
      map.putIfAbsent(dayKey, () => []).add(entry);
    }
    return map;
  }

  Future<SaleDetail?> getDetail(int saleId) => _saleRepo.getSaleDetail(saleId);

  /// Eksekusi pembatalan transaksi (VOID)
  Future<bool> voidSale({
    required Sale sale,
    required String reason,
  }) async {
    if (!canVoid) {
      Get.snackbar('Akses Ditolak', 'Anda tidak memiliki hak akses membatalkan transaksi (pos.void).');
      return false;
    }

    final trimmed = reason.trim();
    if (trimmed.length < 5) {
      Get.snackbar('Validasi Gagal', 'Alasan pembatalan wajib diisi minimal 5 karakter.');
      return false;
    }

    isVoiding.value = true;
    try {
      final updated = await _saleRepo.voidSale(saleId: sale.id, reason: trimmed);

      // Perbarui item di entries lokal secara reaktif
      final idx = entries.indexWhere((e) => e.sale.id == sale.id);
      if (idx != -1) {
        entries[idx] = SaleListEntry(
          sale: updated,
          cashierName: entries[idx].cashierName,
          paymentMethods: entries[idx].paymentMethods,
        );
      }

      // Segarkan ringkasan agregat & harian
      final (startDate, endDate) = getActiveDateRange();
      final status = selectedStatusFilter.value;
      final query = searchQuery.value.trim().isEmpty ? null : searchQuery.value.trim();

      final cashierId = selectedCashierId.value;
      aggregateSummary.value = await _saleRepo.getAggregateSummary(
        startDate: startDate,
        endDate: endDate,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );

      final now = DateTime.now();
      final from = startDate ?? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 180));
      final to = endDate ?? DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      final summaries = await _saleRepo.getDailySummaries(
        from: from,
        to: to,
        status: status,
        searchQuery: query,
        cashierId: cashierId,
      );
      dailySummaries.assignAll({for (final s in summaries) s.day: s});

      Get.snackbar(
        'Transaksi Dibatalkan',
        'Transaksi ${sale.invoiceNo} berhasil di-void. Stok barang telah dikembalikan.',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } catch (e) {
      Get.snackbar('Gagal Void', 'Pembatalan transaksi gagal: $e', snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isVoiding.value = false;
    }
  }

  ReceiptData buildReceipt(SaleDetail detail, {bool isReprint = true}) {
    return buildReceiptData(
      store: AuthService.to.currentStore.value,
      cashierName: detail.cashierName,
      sale: detail.sale,
      items: detail.items,
      payments: detail.payments,
      isReprint: isReprint,
    );
  }

  Future<void> printReceipt(ReceiptData receipt) async {
    final result = await ReceiptActions.print(receipt);
    if (result.success) {
      Get.snackbar(
        'Berhasil',
        'Struk berhasil dicetak.',
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> savePdf(ReceiptData receipt) async {
    try {
      await ReceiptActions.savePdf(receipt);
    } catch (e) {
      Get.snackbar('PDF', 'Gagal menyimpan / membagikan PDF: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}
