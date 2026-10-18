import 'package:get/get.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/license_repository.dart';
import '../../data/repositories/opname_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/role_repository.dart';
import '../../data/repositories/sale_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../data/repositories/unit_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../features/entitlement_provider.dart';
import '../permissions/permission_service.dart';
import '../services/audit_service.dart';
import '../services/auth_service.dart';
import '../services/feature_gate.dart';
import '../printing/printer_manager.dart';
import '../services/scanner/scanner_service.dart';
import '../../modules/pos/controllers/pos_controller.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // Database singleton
    final db = Get.isRegistered<AppDatabase>()
        ? Get.find<AppDatabase>()
        : Get.put<AppDatabase>(AppDatabase(), permanent: true);

    // Register all repositories with lazyPut(fenix: true)
    Get.lazyPut<StoreRepository>(() => StoreRepository(db.storeDao), fenix: true);
    Get.lazyPut<UserRepository>(() => UserRepository(db.userDao), fenix: true);
    Get.lazyPut<RoleRepository>(() => RoleRepository(db.roleDao), fenix: true);
    Get.lazyPut<ProductRepository>(
      () => ProductRepository(db.productDao, settingsDao: db.settingsDao, storeDao: db.storeDao),
      fenix: true,
    );
    Get.lazyPut<CategoryRepository>(() => CategoryRepository(db.categoryDao), fenix: true);
    Get.lazyPut<UnitRepository>(() => UnitRepository(db.unitDao), fenix: true);
    Get.lazyPut<SupplierRepository>(() => SupplierRepository(db.supplierDao), fenix: true);
    Get.lazyPut<SaleRepository>(() => SaleRepository(db, db.saleDao, db.productDao, db.stockDao), fenix: true);
    Get.lazyPut<PurchaseRepository>(() => PurchaseRepository(db.purchaseDao), fenix: true);
    Get.lazyPut<StockRepository>(() => StockRepository(db, db.stockDao, db.productDao), fenix: true);
    Get.lazyPut<OpnameRepository>(() => OpnameRepository(db.opnameDao), fenix: true);
    Get.lazyPut<SettingsRepository>(() => SettingsRepository(db.settingsDao), fenix: true);
    Get.lazyPut<AuditRepository>(() => AuditRepository(db.auditDao), fenix: true);
    Get.lazyPut<LicenseRepository>(() => LicenseRepository(db.licenseDao), fenix: true);
    Get.lazyPut<PosController>(() => PosController(), fenix: true);

    // Entitlement Provider (dapat ditukar implementasinya dalam satu baris)
    Get.lazyPut<EntitlementProvider>(
      () => SimulatedEntitlementProvider(Get.find<LicenseRepository>()),
      fenix: true,
    );

    // Audit Service
    if (!Get.isRegistered<AuditService>()) {
      Get.put<AuditService>(
        AuditService(Get.find<AuditRepository>()),
        permanent: true,
      );
    }

    // FeatureGate Service
    if (!Get.isRegistered<FeatureGate>()) {
      Get.put<FeatureGate>(
        FeatureGate(Get.find<EntitlementProvider>()),
        permanent: true,
      );
    }

    // Permission Service
    if (!Get.isRegistered<PermissionService>()) {
      Get.put<PermissionService>(
        PermissionService(Get.find<RoleRepository>()),
        permanent: true,
      );
    }

    // Auth Service
    if (!Get.isRegistered<AuthService>()) {
      Get.put<AuthService>(
        AuthService(Get.find<StoreRepository>(), Get.find<UserRepository>()),
        permanent: true,
      );
    }

    // Scanner Service (HID Keyboard + Camera)
    if (!Get.isRegistered<ScannerService>()) {
      Get.put<ScannerService>(
        ScannerService(),
        permanent: true,
      );
    }

    // Printer Manager (ESC/POS & PDF fallback)
    if (!Get.isRegistered<PrinterManager>()) {
      Get.put<PrinterManager>(
        PrinterManager(),
        permanent: true,
      );
    }
  }
}
