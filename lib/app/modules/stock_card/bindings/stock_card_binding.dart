import 'package:get/get.dart';

import '../controllers/stock_card_controller.dart';

class StockCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockCardController>(
      () => StockCardController(),
    );
  }
}
