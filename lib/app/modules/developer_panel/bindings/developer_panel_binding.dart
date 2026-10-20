import 'package:get/get.dart';

import '../controllers/developer_panel_controller.dart';

class DeveloperPanelBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeveloperPanelController>(
      () => DeveloperPanelController(),
    );
  }
}
