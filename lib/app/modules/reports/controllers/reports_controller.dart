import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/local/daos/report_dao.dart';
import '../../../data/models/export_models.dart';
import '../../../data/repositories/export_repository.dart';
import '../../../data/repositories/report_repository.dart';
import '../../../data/services/export_file_service.dart';
import '../../../routes/app_pages.dart';

/// Pilihan preset rentang tanggal untuk Laporan Lengkap
enum ReportDatePreset {
  today,
  sevenDays,
  thisMonth,
  lastMonth,
  custom;

  String get label {
    switch (this) {
      case ReportDatePreset.today:
        return 'Hari Ini';
      case ReportDatePreset.sevenDays:
        return '7 Hari';
      case ReportDatePreset.thisMonth:
        return 'Bulan Ini';
      case ReportDatePreset.lastMonth:
        return 'Bulan Lalu';
      case ReportDatePreset.custom:
        return 'Kustom';
    }
  }
}

class ReportsController extends GetxController {
  final ReportRepository _reportRepo = Get.find<ReportRepository>();

  // State Laporan Dasar
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final reports = <DailySalesReportEntry>[].obs;

  // State Tab Navigasi (0 = Laporan Dasar, 1 = Laporan Lengkap)
  final selectedTabIndex = 0.obs;

  // State Laporan Lengkap (Semi-Premium)
  final selectedPreset = ReportDatePreset.today.obs;
  final customDateRange = Rxn<DateTimeRange>();
  final topSellingSortBy = 'qty'.obs; // 'qty' | 'revenue'
  final fullReport = Rxn<FullReportData>();
  final isLoadingFullReport = false.obs;
  final fullReportError = ''.obs;

  bool get canViewBasic {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportViewBasic);
  }

  bool get canViewProfit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportViewProfit);
  }

  bool get isFullReportsUnlocked {
    if (!Get.isRegistered<FeatureGate>()) return false;
    return FeatureGate.to.isEnabled(Feature.fullReports);
  }

  bool get canExport {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportExport);
  }

  bool get isSoloMode {
    if (!Get.isRegistered<AuthService>()) return false;
    return AuthService.to.isSoloMode;
  }

  int get totalRevenue30Days =>
      reports.fold<int>(0, (sum, item) => sum + item.omzet);

  int get totalTx30Days =>
      reports.fold<int>(0, (sum, item) => sum + item.txCount);

  @override
  void onInit() {
    super.onInit();
    loadReports();
    if (isFullReportsUnlocked) {
      loadFullReport();
    }
  }

  /// Memuat data laporan harian dasar 30 hari
  Future<void> loadReports() async {
    if (!canViewBasic) {
      isLoading.value = false;
      errorMessage.value =
          'Akses ditolak: Anda tidak memiliki hak akses melihat laporan dasar (report.view_basic).';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      final data = await _reportRepo.getDailySalesReport();
      reports.assignAll(data);
    } catch (e) {
      errorMessage.value = 'Gagal memuat laporan: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// Menghitung rentang waktu [from, to) berdasarkan preset waktu lokal
  ({DateTime from, DateTime to}) getDateRangeForPreset(
    ReportDatePreset preset, {
    DateTime? customNow,
  }) {
    final now = customNow ?? DateTime.now();
    switch (preset) {
      case ReportDatePreset.today:
        final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return (from: from, to: to);
      case ReportDatePreset.sevenDays:
        final from = DateTime(now.year, now.month, now.day - 6, 0, 0, 0);
        final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return (from: from, to: to);
      case ReportDatePreset.thisMonth:
        final from = DateTime(now.year, now.month, 1, 0, 0, 0);
        final to = DateTime(now.year, now.month + 1, 1, 0, 0, 0);
        return (from: from, to: to);
      case ReportDatePreset.lastMonth:
        final from = DateTime(now.year, now.month - 1, 1, 0, 0, 0);
        final to = DateTime(now.year, now.month, 1, 0, 0, 0);
        return (from: from, to: to);
      case ReportDatePreset.custom:
        if (customDateRange.value != null) {
          final start = customDateRange.value!.start;
          final end = customDateRange.value!.end;
          final from = DateTime(start.year, start.month, start.day, 0, 0, 0);
          final to = DateTime(end.year, end.month, end.day + 1, 0, 0, 0);
          return (from: from, to: to);
        }
        final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return (from: from, to: to);
    }
  }

  /// Memuat data laporan lengkap untuk rentang terpilih
  Future<void> loadFullReport() async {
    if (!isFullReportsUnlocked) {
      return;
    }

    if (!canViewBasic) {
      fullReportError.value =
          'Akses ditolak: Anda tidak memiliki hak akses melihat laporan (report.view_basic).';
      return;
    }

    isLoadingFullReport.value = true;
    fullReportError.value = '';

    try {
      final range = getDateRangeForPreset(selectedPreset.value);
      final data = await _reportRepo.getFullReport(
        from: range.from,
        to: range.to,
        topSellingSortBy: topSellingSortBy.value,
        isSoloMode: isSoloMode,
      );
      fullReport.value = data;
    } catch (e) {
      fullReportError.value = 'Gagal memuat laporan lengkap: $e';
    } finally {
      isLoadingFullReport.value = false;
    }
  }

  /// Mengubah preset tanggal
  void setPreset(ReportDatePreset preset) {
    if (selectedPreset.value == preset && preset != ReportDatePreset.custom) return;
    selectedPreset.value = preset;
    loadFullReport();
  }

  /// Menetapkan rentang tanggal kustom
  void setCustomRange(DateTimeRange range) {
    customDateRange.value = range;
    selectedPreset.value = ReportDatePreset.custom;
    loadFullReport();
  }

  /// Mengubah pengurutan produk terlaris ('qty' atau 'revenue')
  void setTopSellingSortBy(String sortBy) {
    if (topSellingSortBy.value == sortBy) return;
    topSellingSortBy.value = sortBy;
    loadFullReport();
  }

  /// Tindakan Ekspor Laporan Lengkap:
  /// - Gating Semi-Premium (`Feature.fullReports`)
  /// - Gating Hak Akses (`report.export`)
  /// - Dialog pilihan format CSV atau Excel (.xlsx)
  /// - Proses penyimpanan berkas dan aksi pembagian
  void handleExport() {
    if (!isFullReportsUnlocked) {
      FeatureGate.to.requireFeature(Feature.fullReports);
      return;
    }

    if (!canExport) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengekspor data laporan (report.export).',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
        margin: const EdgeInsets.all(16),
      );
      return;
    }

    if (fullReport.value == null) {
      Get.snackbar(
        'Perhatian',
        'Data laporan belum selesai dimuat. Silakan tunggu beberapa saat.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.dialog(
      AlertDialog(
        icon: const Icon(Icons.file_download_outlined, size: 36, color: Colors.blue),
        title: const Text('Ekspor Laporan Lengkap'),
        content: const Text(
          'Pilih format berkas untuk mengekspor data laporan lengkap (ringkasan, produk terlaris, kategori, metode pembayaran, kasir, jam operasional, dan status stok):',
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Get.back();
              _processExport(ExportFormat.csv);
            },
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('CSV (.csv)'),
          ),
          FilledButton.icon(
            onPressed: () {
              Get.back();
              _processExport(ExportFormat.xlsx);
            },
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Excel (.xlsx)'),
          ),
        ],
      ),
    );
  }

  Future<void> _processExport(ExportFormat format) async {
    try {
      Get.dialog(
        const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Menyiapkan dan mengekspor berkas...'),
                ],
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );

      final exportRepo = Get.find<ExportRepository>();
      final result = await exportRepo.exportFullReport(fullReport.value!, format: format);
      final savedPath = await ExportFileService.saveFile(
        fileName: result.fileName,
        bytes: result.bytes,
      );

      if (Get.isDialogOpen == true) {
        Get.back(); // Tutup loading dialog
      }

      if (savedPath != null && savedPath.isNotEmpty) {
        Get.dialog(
          AlertDialog(
            icon: const Icon(Icons.check_circle_outline, size: 40, color: Colors.green),
            title: const Text('Ekspor Berhasil'),
            content: Text(
              'Berkas laporan ${format.displayName} berhasil disimpan ke:\n$savedPath',
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Get.back(),
                child: const Text('Tutup'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Get.back();
                  await ExportFileService.openOrShareFile(
                    savedPath,
                    subject: 'Laporan POS Me - ${result.fileName}',
                  );
                },
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Buka / Bagikan'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      Get.snackbar(
        'Gagal Mengekspor',
        'Terjadi kendala saat mengekspor: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
        margin: const EdgeInsets.all(16),
      );
    }
  }

  void openDailySalesHistory(DailySalesReportEntry entry) {
    Get.toNamed(Routes.SALES_HISTORY, arguments: {'date': entry.date});
  }
}
