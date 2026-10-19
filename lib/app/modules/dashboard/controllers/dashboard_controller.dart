import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/repositories/report_repository.dart';

class DashboardController extends GetxController {
  final ReportRepository _reportRepo = Get.find<ReportRepository>();

  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final dashboardData = Rxn<DashboardData>();

  bool get canViewProfit {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.reportViewProfit);
  }

  bool get isFullReportsUnlocked {
    if (!Get.isRegistered<FeatureGate>()) return false;
    return FeatureGate.to.isEnabled(Feature.fullReports);
  }

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
    } catch (e) {
      errorMessage.value = 'Gagal menyegarkan data: $e';
    }
  }
}
