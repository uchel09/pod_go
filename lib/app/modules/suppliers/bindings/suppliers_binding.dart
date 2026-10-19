import 'package:get/get.dart';

import '../controllers/suppliers_controller.dart';

class SuppliersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SuppliersController>(
      () => SuppliersController(),
    );
  }
}
