import 'package:get/get.dart';

import '../controllers/checkout_simulation_controller.dart';

class CheckoutSimulationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CheckoutSimulationController>(
      () => CheckoutSimulationController(),
    );
  }
}
