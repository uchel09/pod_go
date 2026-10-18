import 'package:get/get.dart';

import '../controllers/pos_controller.dart';

class PosBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PosController>()) {
      Get.put<PosController>(PosController(), permanent: true);
    }
  }
}
