import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:intl/date_symbol_data_local.dart';

import 'app/core/bindings/initial_binding.dart';
import 'app/core/config/app_config.dart';
import 'app/core/permissions/permission_service.dart';
import 'app/core/services/auth_service.dart';
import 'app/core/services/feature_gate.dart';
import 'app/core/theme/app_theme.dart';
import 'app/core/utils/device_id_service.dart';
import 'app/data/repositories/category_repository.dart';
import 'app/data/repositories/role_repository.dart';
import 'app/data/repositories/unit_repository.dart';
import 'app/data/seeders/master_data_seeder.dart';
import 'app/data/seeders/role_seeder.dart';
import 'app/routes/app_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Indonesian Date Formatting
  await initializeDateFormatting('id_ID', null);

  // Initialize Core Preferences Services
  await Get.putAsync(() => ThemeService().init());
  await Get.putAsync(() => DeviceIdService().init());

  // Setup Database, Repositories, and Core Services
  InitialBinding().dependencies();
  await RoleSeeder.seedDefaultRoles(Get.find<RoleRepository>());
  await MasterDataSeeder.seed(Get.find<CategoryRepository>(), Get.find<UnitRepository>());
  await FeatureGate.to.init();
  await AuthService.to.init();
  await PermissionService.to.init();

  runApp(const PosMeApp());
}

class PosMeApp extends StatelessWidget {
  const PosMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      initialBinding: InitialBinding(),
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeService.to.themeMode,
      initialRoute: AppPages.INITIAL,
      getPages: AppPages.routes,
    );
  }
}
