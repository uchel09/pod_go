import 'package:get/get.dart';

import '../controllers/sale_return_controller.dart';

class SaleReturnBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SaleReturnController>(
      () => SaleReturnController(),
    );
  }
}
