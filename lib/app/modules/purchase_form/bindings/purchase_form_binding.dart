import 'package:get/get.dart';

import '../controllers/purchase_form_controller.dart';

class PurchaseFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseFormController>(
      () => PurchaseFormController(),
    );
  }
}
