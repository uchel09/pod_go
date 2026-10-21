import 'package:get/get.dart';

import '../controllers/expense_form_controller.dart';

class ExpenseFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ExpenseFormController>(
      () => ExpenseFormController(),
    );
  }
}
