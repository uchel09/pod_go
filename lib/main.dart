import 'package:flutter/foundation.dart';
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
import 'app/core/utils/error_logger.dart';
import 'app/data/repositories/category_repository.dart';
import 'app/data/repositories/role_repository.dart';
import 'app/data/repositories/unit_repository.dart';
import 'app/data/seeders/master_data_seeder.dart';
import 'app/data/seeders/role_seeder.dart';
import 'app/routes/app_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup Global Error Handlers (Resilience & Logging)
  FlutterError.onError = AppErrorLogger.onFlutterError;
  PlatformDispatcher.instance.onError = AppErrorLogger.onPlatformError;

  // Custom User-Friendly Error Widget (mencegah layar merah crash)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'Terjadi Kendala Tampilan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                kDebugMode
                    ? details.exceptionAsString()
                    : 'Aplikasi mengalami kendala teknis sementara. Data Anda tetap aman.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  };

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
