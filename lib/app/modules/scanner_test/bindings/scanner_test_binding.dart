import 'package:get/get.dart';

import '../controllers/scanner_test_controller.dart';

class ScannerTestBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ScannerTestController>(
      () => ScannerTestController(),
    );
  }
}
