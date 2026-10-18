import 'package:get/get.dart';

import '../controllers/units_controller.dart';

class UnitsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UnitsController>(
      () => UnitsController(),
    );
  }
}
