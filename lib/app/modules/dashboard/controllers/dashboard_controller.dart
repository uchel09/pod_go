import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/models/backup_models.dart';
import '../../../data/repositories/backup_repository.dart';
import '../../../data/repositories/report_repository.dart';

class DashboardController extends GetxController {
  final ReportRepository _reportRepo = Get.find<ReportRepository>();
  BackupRepository? get _backupRepo =>
      Get.isRegistered<BackupRepository>() ? Get.find<BackupRepository>() : null;

  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final dashboardData = Rxn<DashboardData>();
  final lastBackupInfo = Rxn<BackupInfo>();

  bool get canViewProfit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportViewProfit);
  }

  bool get isFullReportsUnlocked {
    if (!Get.isRegistered<FeatureGate>()) return false;
    return FeatureGate.to.isEnabled(Feature.fullReports);
  }

  bool get canManageBackup {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.backupManage);
  }

  /// Banner pengingat tampil bila user berizin `backup.manage` DAN
  /// data belum pernah dibackup atau sudah lebih dari 7 hari sejak backup terakhir.
  bool get shouldShowBackupReminder {
    if (!canManageBackup) return false;
    final info = lastBackupInfo.value;
    if (info == null) return true;
    return info.daysAgo >= 7;
  }

  int get backupDaysAgo => lastBackupInfo.value?.daysAgo ?? 0;

  @override
  void onInit() {
    super.onInit();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final data = await _reportRepo.getDashboardData();
      dashboardData.value = data;
      await _checkBackupStatus();
    } catch (e) {
      errorMessage.value = 'Gagal memuat data dashboard: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshDashboard() async {
    try {
      final data = await _reportRepo.getDashboardData();
      dashboardData.value = data;
      errorMessage.value = '';
      await _checkBackupStatus();
    } catch (e) {
      errorMessage.value = 'Gagal menyegarkan data: $e';
    }
  }

  Future<void> _checkBackupStatus() async {
    if (!canManageBackup) return;
    try {
      if (_backupRepo != null) {
        lastBackupInfo.value = await _backupRepo!.getLastBackupInfo();
      }
    } catch (_) {}
  }
}
