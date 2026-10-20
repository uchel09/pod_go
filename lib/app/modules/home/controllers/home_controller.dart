import 'package:get/get.dart';

import '../../../data/repositories/backup_repository.dart';

class HomeController extends GetxController {
  final selectedIndex = 0.obs;

  void changeTabIndex(int index) {
    selectedIndex.value = index;
  }

  @override
  void onReady() {
    super.onReady();
    _triggerAutoBackup();
  }

  void _triggerAutoBackup() {
    if (Get.isRegistered<BackupRepository>()) {
      Get.find<BackupRepository>().runAutoBackupIfNeeded();
    }
  }
}
