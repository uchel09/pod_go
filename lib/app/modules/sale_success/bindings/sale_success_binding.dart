import 'package:get/get.dart';

import '../controllers/sale_success_controller.dart';

class SaleSuccessBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SaleSuccessController>(
      () => SaleSuccessController(),
    );
  }
}
