import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/models/backup_models.dart';
import '../../../data/repositories/backup_repository.dart';
import '../../../data/services/export_file_service.dart';
import '../../../routes/app_pages.dart';
import '../../../core/bindings/initial_binding.dart';

class BackupController extends GetxController {
  final BackupRepository _backupRepo = Get.find<BackupRepository>();

  final isLoading = true.obs;
  final isBackingUp = false.obs;
  final isRestoring = false.obs;
  final isValidatingRestore = false.obs;
  final isTestingAutoBackup = false.obs;
  final isSavingAutoBackup = false.obs;
  final errorMessage = ''.obs;

  final lastBackupInfo = Rxn<BackupInfo>();
  final latestBackupResult = Rxn<BackupResult>();
  final restorePreview = Rxn<RestorePreview>();
  final autoBackupConfig = const AutoBackupConfig(enabled: false).obs;

  bool get canManageBackup {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.backupManage);
  }

  bool get isAutoBackupUnlocked {
    if (!Get.isRegistered<FeatureGate>()) return false;
    return FeatureGate.to.isEnabled(Feature.autoBackup);
  }

  @override
  void onInit() {
    super.onInit();
    _checkInitialAccess();
    loadLastBackupInfo();
    loadAutoBackupConfig();
  }

  void _checkInitialAccess() {
    if (!canManageBackup) {
      if (Get.context != null) {
        Get.snackbar(
          'Akses Ditolak',
          'Anda tidak memiliki izin untuk mengelola backup data.',
          snackPosition: SnackPosition.BOTTOM,
        );
        Get.back();
      }
    }
  }

  Future<void> loadLastBackupInfo() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final info = await _backupRepo.getLastBackupInfo();
      lastBackupInfo.value = info;
    } catch (e) {
      errorMessage.value = 'Gagal memuat status backup: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadAutoBackupConfig() async {
    try {
      final config = await _backupRepo.getAutoBackupConfig();
      autoBackupConfig.value = config;
    } catch (_) {}
  }

  // =========================================================================
  // BACKUP MANUAL
  // =========================================================================

  Future<void> createBackup() async {
    if (!canManageBackup) {
      if (Get.context != null) {
        Get.snackbar('Akses Ditolak', 'Anda tidak memiliki hak akses backup.');
      }
      return;
    }

    isBackingUp.value = true;
    errorMessage.value = '';
    try {
      final result = await _backupRepo.createBackup();
      latestBackupResult.value = result;
      await loadLastBackupInfo();

      if (Get.context != null) {
        Get.snackbar(
          'Backup Berhasil',
          'Berkas cadangan data (${result.formattedSize}) berhasil dibuat.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      errorMessage.value = e.toString();
      if (Get.context != null) {
        Get.snackbar(
          'Gagal Membuat Backup',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
        );
      }
    } finally {
      isBackingUp.value = false;
    }
  }

  Future<void> saveToFolder() async {
    final result = latestBackupResult.value;
    if (result == null) return;

    try {
      final path = await ExportFileService.saveFile(
        fileName: result.fileName,
        bytes: result.bytes,
      );

      if (path != null && Get.context != null) {
        Get.snackbar(
          'Berkas Disimpan',
          'Backup tersimpan di: $path',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar('Gagal Menyimpan', e.toString());
      }
    }
  }

  Future<void> shareBackup() async {
    final result = latestBackupResult.value;
    if (result == null) return;

    try {
      await ExportFileService.shareFile(
        result.filePath,
        subject: 'Backup POS Me - ${result.fileName}',
        text: 'Berkas cadangan data POS Me (${result.fileName}) dibuat pada ${result.createdAt}',
      );
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar('Gagal Membagikan', e.toString());
      }
    }
  }

  // =========================================================================
  // PEMULIHAN (RESTORE)
  // =========================================================================

  Future<RestorePreview?> pickAndValidateRestoreFile() async {
    if (!canManageBackup) {
      if (Get.context != null) {
        Get.snackbar('Akses Ditolak', 'Anda tidak memiliki hak akses restore.');
      }
      return null;
    }

    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih Berkas Backup (.zip) untuk Dipulihkan',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (files.isEmpty) {
        return null;
      }

      final path = files.first.path;
      if (path == null) {
        if (Get.context != null) {
          Get.snackbar('Gagal Membaca File', 'Lokasi berkas tidak dapat diakses.');
        }
        return null;
      }

      isValidatingRestore.value = true;
      final file = File(path);
      final preview = await _backupRepo.validateBackupForRestore(file);
      restorePreview.value = preview;
      return preview;
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar(
          'Pemeriksaan Backup Gagal',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
      return null;
    } finally {
      isValidatingRestore.value = false;
    }
  }

  Future<bool> executeRestore() async {
    final preview = restorePreview.value;
    if (preview == null) return false;

    isRestoring.value = true;
    try {
      await _backupRepo.executeRestore(preview);
      restorePreview.value = null;
      return true;
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar(
          'Gagal Memulihkan Data',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 6),
        );
      }
      return false;
    } finally {
      isRestoring.value = false;
    }
  }

  /// Melakukan reinisialisasi bersih dan navigasi ulang ke root aplikasi
  void reinitApp() {
    try {
      InitialBinding().dependencies();
    } catch (_) {}
    Get.offAllNamed(Routes.HOME);
  }

  // =========================================================================
  // PENCADANGAN OTOMATIS (AUTO-BACKUP)
  // =========================================================================

  Future<void> toggleAutoBackup(bool enabled) async {
    if (enabled && !isAutoBackupUnlocked) {
      FeatureGate.to.requireFeature(Feature.autoBackup);
      return;
    }

    if (enabled && (autoBackupConfig.value.folderPath == null || autoBackupConfig.value.folderPath!.isEmpty)) {
      if (Get.context != null) {
        Get.snackbar(
          'Folder Belum Dipilih',
          'Silakan tentukan folder penyimpanan auto-backup terlebih dahulu.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      await pickAutoBackupFolder();
      return;
    }

    final newConfig = autoBackupConfig.value.copyWith(enabled: enabled);
    await _saveConfig(newConfig);
  }

  Future<void> pickAutoBackupFolder() async {
    if (!isAutoBackupUnlocked) {
      FeatureGate.to.requireFeature(Feature.autoBackup);
      return;
    }

    try {
      final folderPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Penyimpanan Auto-Backup (Sinkron Cloud)',
      );

      if (folderPath != null && folderPath.isNotEmpty) {
        final newConfig = autoBackupConfig.value.copyWith(
          folderPath: folderPath,
          enabled: true,
        );
        await _saveConfig(newConfig);
      }
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar('Gagal Memilih Folder', e.toString());
      }
    }
  }

  Future<void> updateSchedule(String schedule) async {
    final newConfig = autoBackupConfig.value.copyWith(schedule: schedule);
    await _saveConfig(newConfig);
  }

  Future<void> updateMaxFiles(int maxFiles) async {
    final newConfig = autoBackupConfig.value.copyWith(maxFiles: maxFiles);
    await _saveConfig(newConfig);
  }

  Future<void> _saveConfig(AutoBackupConfig newConfig) async {
    isSavingAutoBackup.value = true;
    try {
      await _backupRepo.saveAutoBackupConfig(newConfig);
      autoBackupConfig.value = newConfig;
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar('Gagal Menyimpan Pengaturan', e.toString());
      }
    } finally {
      isSavingAutoBackup.value = false;
    }
  }

  Future<void> testAutoBackupNow() async {
    if (!isAutoBackupUnlocked) {
      FeatureGate.to.requireFeature(Feature.autoBackup);
      return;
    }

    final folder = autoBackupConfig.value.folderPath;
    if (folder == null || folder.isEmpty) {
      if (Get.context != null) {
        Get.snackbar('Folder Belum Dipilih', 'Pilih folder tujuan terlebih dahulu.');
      }
      return;
    }

    isTestingAutoBackup.value = true;
    try {
      final result = await _backupRepo.testAutoBackup(
        folderPath: folder,
        maxFiles: autoBackupConfig.value.maxFiles,
      );
      await loadLastBackupInfo();

      if (Get.context != null) {
        Get.snackbar(
          'Uji Auto-Backup Berhasil',
          'Berkas ${result.fileName} (${result.formattedSize}) berhasil ditulis ke folder tujuan dan rotasi berkas berjalan lancar.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar(
          'Uji Auto-Backup Gagal',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      isTestingAutoBackup.value = false;
    }
  }
}
