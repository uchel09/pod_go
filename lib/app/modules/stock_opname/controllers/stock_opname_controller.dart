import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/local/daos/opname_dao.dart';
import '../../../data/repositories/opname_repository.dart';
import '../../../routes/app_pages.dart';

class StockOpnameController extends GetxController {
  final OpnameRepository _opnameRepo = Get.find<OpnameRepository>();

  final opnames = <OpnameSummaryEntry>[].obs;
  final isLoading = false.obs;
  final isSaving = false.obs;

  final searchQuery = ''.obs;
  final selectedStatus = 'all'.obs; // 'all', 'draft', 'final'
  final selectedDateRange = Rxn<DateTimeRange>();

  final currentPage = 0.obs;
  final hasMore = true.obs;
  static const int pageSize = 20;

  bool get canManage => PermissionService.to.can(PermissionKeys.stockOpname);
  bool get hasFeature => FeatureGate.to.isEnabled(Feature.stockOpname);

  @override
  void onInit() {
    super.onInit();
    loadOpnames(refresh: true);
  }

  Future<void> loadOpnames({bool refresh = false}) async {
    if (isLoading.value) return;

    if (refresh) {
      currentPage.value = 0;
      hasMore.value = true;
      opnames.clear();
    }

    if (!hasMore.value && !refresh) return;

    isLoading.value = true;
    try {
      DateTime? start;
      DateTime? end;
      if (selectedDateRange.value != null) {
        start = DateTime(
          selectedDateRange.value!.start.year,
          selectedDateRange.value!.start.month,
          selectedDateRange.value!.start.day,
        );
        end = DateTime(
          selectedDateRange.value!.end.year,
          selectedDateRange.value!.end.month,
          selectedDateRange.value!.end.day,
          23,
          59,
          59,
        );
      }

      final pageData = await _opnameRepo.getOpnamesPaged(
        limit: pageSize,
        offset: currentPage.value * pageSize,
        status: selectedStatus.value == 'all' ? null : selectedStatus.value,
        startDate: start,
        endDate: end,
        searchQuery: searchQuery.value,
      );

      if (pageData.length < pageSize) {
        hasMore.value = false;
      }

      if (refresh) {
        opnames.assignAll(pageData);
      } else {
        opnames.addAll(pageData);
      }
      currentPage.value++;
    } catch (e) {
      Get.snackbar(
        'Gagal Memuat Opname',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (!isLoading.value && hasMore.value) {
      await loadOpnames();
    }
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    loadOpnames(refresh: true);
  }

  void onStatusChanged(String status) {
    selectedStatus.value = status;
    loadOpnames(refresh: true);
  }

  void setDateRange(DateTimeRange? range) {
    selectedDateRange.value = range;
    loadOpnames(refresh: true);
  }

  /// Memulai sesi opname baru
  Future<void> createNewOpname() async {
    if (isSaving.value) return;

    if (!hasFeature) {
      FeatureGate.to.requireFeature(Feature.stockOpname);
      return;
    }

    if (!canManage) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengelola Stock Opname.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    isSaving.value = true;
    try {
      final newOpname = await _opnameRepo.createOpname();
      // Segarkan daftar di background dan navigasikan langsung ke halaman hitung
      loadOpnames(refresh: true);
      Get.toNamed(Routes.OPNAME_DETAIL, arguments: {'opnameId': newOpname.id});
    } catch (e) {
      Get.snackbar(
        'Gagal Membuat Opname',
        e is AppException ? e.message : e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isSaving.value = false;
    }
  }

  /// Menghapus sesi draft opname
  Future<void> deleteDraft(OpnameSummaryEntry entry) async {
    if (entry.isFinal) {
      Get.snackbar('Aksi Ditolak', 'Opname yang sudah final tidak dapat dihapus.');
      return;
    }

    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Hapus Draft Opname?'),
        content: Text(
          'Sesi opname "${entry.code}" beserta seluruh data hitungan akan dihapus secara permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _opnameRepo.deleteOpname(entry.opname.id);
      opnames.removeWhere((o) => o.opname.id == entry.opname.id);
      Get.snackbar(
        'Berhasil Dihapus',
        'Draft opname "${entry.code}" telah dihapus.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Gagal Menghapus',
        e is AppException ? e.message : e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// Mengelompokkan opname per hari
  Map<String, List<OpnameSummaryEntry>> get groupedOpnames {
    final Map<String, List<OpnameSummaryEntry>> map = {};
    for (final item in opnames) {
      final key = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(item.date);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }
}
