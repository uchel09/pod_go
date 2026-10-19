import 'package:get/get.dart';

import '../controllers/import_wizard_controller.dart';

class ImportWizardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ImportWizardController>(
      () => ImportWizardController(),
    );
  }
}
