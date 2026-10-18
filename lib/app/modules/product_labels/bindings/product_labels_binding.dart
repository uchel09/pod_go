import 'package:get/get.dart';

import '../controllers/product_labels_controller.dart';

class ProductLabelsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProductLabelsController>(
      () => ProductLabelsController(),
    );
  }
}
