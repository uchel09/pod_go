import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/models/export_models.dart';
import '../../../data/repositories/export_repository.dart';
import '../../../data/services/export_file_service.dart';
import '../../../data/services/import_template_service.dart';
import '../../../routes/app_pages.dart';

class ImportExportController extends GetxController {
  final isDownloading = false.obs;
  final isExporting = false.obs;

  @override
  void onInit() {
    super.onInit();
    _checkInitialAccess();
  }

  /// Memeriksa ketersediaan fitur dan izin pengguna
  void _checkInitialAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        FeatureGate.to.requireFeature(Feature.importExport);
        return;
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      final hasImport = PermissionService.to.can(PermissionKeys.importManage);
      final hasExport = PermissionService.to.can(PermissionKeys.reportExport);
      if (!hasImport && !hasExport) {
        Get.snackbar(
          'Akses Ditolak',
          'Anda tidak memiliki izin untuk mengelola import atau export data.',
          snackPosition: SnackPosition.BOTTOM,
        );
        Get.back();
      }
    }
  }

  bool get canImport {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.importManage);
  }

  bool get canExport {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportExport);
  }

  bool get canViewAudit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.auditView);
  }

  /// Membuka wizard import untuk jenis entitas tertentu
  void startImport(ImportTemplateType type) {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        FeatureGate.to.requireFeature(Feature.importExport);
        return;
      }
    }

    if (!canImport) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengimpor data (import.manage).',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.toNamed(Routes.IMPORT_WIZARD, arguments: {'type': type});
  }

  /// Mengunduh template baku (CSV atau XLSX) dengan contoh data
  Future<void> downloadTemplate(ImportTemplateType type, {required bool isCsv}) async {
    isDownloading.value = true;
    try {
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final extension = isCsv ? 'csv' : 'xlsx';
      final fileName = '${type.fileNamePrefix}_$dateStr.$extension';

      List<int> bytes;
      if (isCsv) {
        final csvStr = ImportTemplateService.generateCsv(type);
        bytes = csvStr.codeUnits;
      } else {
        bytes = ImportTemplateService.generateXlsx(type);
      }

      final savedPath = await ImportTemplateService.saveTemplateFile(
        fileName: fileName,
        bytes: bytes,
      );

      if (savedPath != null && savedPath.isNotEmpty) {
        Get.snackbar(
          'Template Tersimpan',
          'Berkas $fileName berhasil diunduh ke:\n$savedPath',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      Get.snackbar(
        'Gagal Menyimpan',
        'Terjadi kendala saat menyimpan template: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isDownloading.value = false;
    }
  }

  // =========================================================================
  // LOGIKA EKSPOR DATA (PROMPT 14B)
  // =========================================================================

  /// Ekspor Katalog Produk langsung (tanpa filter tanggal)
  Future<void> exportProducts(ExportFormat format) async {
    _assertExport();
    await _runExportOperation(
      task: () {
        final repo = Get.find<ExportRepository>();
        return repo.exportProducts(format: format);
      },
      format: format,
      title: 'Katalog Produk',
    );
  }

  /// Membuka dialog pilihan filter rentang tanggal dan format untuk entitas tertentu
  void showExportFilterDialog(ExportType type) {
    _assertExport();

    if (type == ExportType.auditLog && !canViewAudit) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk melihat log aktivitas (audit.view).',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // Variabel state dialog
    int selectedPreset = 2; // 0 = Hari Ini, 1 = 7 Hari, 2 = Bulan Ini, 3 = Bulan Lalu, 4 = Semua
    ExportFormat selectedFormat = ExportFormat.xlsx;

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            icon: const Icon(Icons.file_download_outlined, size: 36, color: Colors.blue),
            title: Text('Ekspor ${type.displayName}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih Rentang Waktu Data:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Hari Ini'),
                          selected: selectedPreset == 0,
                          onSelected: (v) => setState(() => selectedPreset = 0),
                        ),
                        ChoiceChip(
                          label: const Text('7 Hari Terakhir'),
                          selected: selectedPreset == 1,
                          onSelected: (v) => setState(() => selectedPreset = 1),
                        ),
                        ChoiceChip(
                          label: const Text('Bulan Ini'),
                          selected: selectedPreset == 2,
                          onSelected: (v) => setState(() => selectedPreset = 2),
                        ),
                        ChoiceChip(
                          label: const Text('Bulan Lalu'),
                          selected: selectedPreset == 3,
                          onSelected: (v) => setState(() => selectedPreset = 3),
                        ),
                        ChoiceChip(
                          label: const Text('Semua Data'),
                          selected: selectedPreset == 4,
                          onSelected: (v) => setState(() => selectedPreset = 4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Pilih Format Berkas:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.table_chart_outlined, size: 16),
                          label: const Text('Excel (.xlsx)'),
                          selected: selectedFormat == ExportFormat.xlsx,
                          onSelected: (v) => setState(() => selectedFormat = ExportFormat.xlsx),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.description_outlined, size: 16),
                          label: const Text('CSV (.csv)'),
                          selected: selectedFormat == ExportFormat.csv,
                          onSelected: (v) => setState(() => selectedFormat = ExportFormat.csv),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Get.back(),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Get.back();
                  final range = _resolveDateRange(selectedPreset);
                  _executeExportByType(
                    type: type,
                    format: selectedFormat,
                    from: range.$1,
                    to: range.$2,
                  );
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Mulai Ekspor'),
              ),
            ],
          );
        },
      ),
    );
  }

  (DateTime?, DateTime?) _resolveDateRange(int preset) {
    final now = DateTime.now();
    switch (preset) {
      case 0: // Hari ini
        final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return (from, to);
      case 1: // 7 hari terakhir
        final start = now.subtract(const Duration(days: 6));
        final from = DateTime(start.year, start.month, start.day, 0, 0, 0);
        final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return (from, to);
      case 2: // Bulan ini
        final from = DateTime(now.year, now.month, 1, 0, 0, 0);
        final to = DateTime(now.year, now.month + 1, 1, 0, 0, 0);
        return (from, to);
      case 3: // Bulan lalu
        final from = DateTime(now.year, now.month - 1, 1, 0, 0, 0);
        final to = DateTime(now.year, now.month, 1, 0, 0, 0);
        return (from, to);
      default: // Semua data
        return (null, null);
    }
  }

  void _executeExportByType({
    required ExportType type,
    required ExportFormat format,
    DateTime? from,
    DateTime? to,
  }) {
    final repo = Get.find<ExportRepository>();

    switch (type) {
      case ExportType.product:
        exportProducts(format);
        break;
      case ExportType.sales:
        _runExportOperation(
          task: () => repo.exportSales(format: format, from: from, to: to),
          format: format,
          title: 'Penjualan',
        );
        break;
      case ExportType.stockCard:
        _runExportOperation(
          task: () => repo.exportStockMovements(format: format, from: from, to: to),
          format: format,
          title: 'Kartu Stok',
        );
        break;
      case ExportType.stockOpname:
        _runExportOperation(
          task: () => repo.exportStockOpname(format: format, from: from, to: to),
          format: format,
          title: 'Hasil Opname',
        );
        break;
      case ExportType.purchases:
        _runExportOperation(
          task: () => repo.exportPurchases(format: format, from: from, to: to),
          format: format,
          title: 'Data Pembelian',
        );
        break;
      case ExportType.auditLog:
        _runExportOperation(
          task: () => repo.exportAuditLogs(format: format, from: from, to: to),
          format: format,
          title: 'Log Aktivitas',
        );
        break;
      case ExportType.expenses:
        _runExportOperation(
          task: () => repo.exportExpenses(format: format, from: from, to: to),
          format: format,
          title: 'Pengeluaran Operasional',
        );
        break;
      case ExportType.fullReport:
        // Laporan lengkap diekspor melalui modul reports
        break;
    }
  }

  Future<void> _runExportOperation({
    required Future<ExportResult> Function() task,
    required ExportFormat format,
    required String title,
  }) async {
    isExporting.value = true;
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

    try {
      final result = await task();
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
            title: Text('Ekspor $title Berhasil'),
            content: Text(
              'Berkas ${result.fileName} (${result.rowCount} data) berhasil disimpan ke:\n$savedPath',
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
                    subject: 'Ekspor $title - ${result.fileName}',
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
    } finally {
      isExporting.value = false;
    }
  }

  void _assertExport() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        FeatureGate.to.requireFeature(Feature.importExport);
        return;
      }
    }

    if (!canExport) {
      Get.snackbar(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengekspor data (report.export).',
        snackPosition: SnackPosition.BOTTOM,
      );
      throw Exception('Akses ditolak: report.export');
    }
  }
}
