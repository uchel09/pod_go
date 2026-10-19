import 'package:get/get.dart';

import '../controllers/stock_opname_controller.dart';

class StockOpnameBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockOpnameController>(
      () => StockOpnameController(),
    );
  }
}
