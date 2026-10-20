import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/audit/audit_actions.dart';
import 'package:pos_me/app/core/config/app_config.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/feature_enum.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_keys.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/data/services/payment_gateway.dart';
import 'package:pos_me/app/modules/developer_panel/controllers/developer_panel_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late RoleRepository roleRepo;
  late LicenseRepository licenseRepo;
  late AuditRepository auditRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late SimulatedEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuditService auditService;
  late AuthService authService;
  late PaymentGateway paymentGateway;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-dev-uuid-16a',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db);

    roleRepo = RoleRepository(db.roleDao);
    licenseRepo = LicenseRepository(db.licenseDao);
    Get.put<LicenseRepository>(licenseRepo);

    auditRepo = AuditRepository(db.auditDao);
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);

    await Get.putAsync(() => DeviceIdService().init());

    entitlementProvider = SimulatedEntitlementProvider(licenseRepo);
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate);

    auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService);

    authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService);

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService);

    paymentGateway = SimulatedPaymentGateway(licenseRepo);
    Get.put<PaymentGateway>(paymentGateway);

    // Setup store in 'team' mode to test RBAC correctly
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Uji 16A'),
        mode: Value('team'),
        requireLogin: Value(true),
      ),
    );
    await authService.refreshState();

    // Seed roles
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final kasirRole = await roleRepo.getRoleByName('Kasir');

    final ownerUserId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner_test'),
        displayName: const Value('Owner Test'),
        pinHash: const Value('123456'),
        roleId: Value(ownerRole!.id),
      ),
    );

    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('cashier_test'),
        displayName: const Value('Cashier Test'),
        pinHash: const Value('123456'),
        roleId: Value(kasirRole!.id),
      ),
    );

    // Login as owner by default
    final ownerUser = await userRepo.getUserById(ownerUserId);
    authService.currentUser.value = ownerUser;
    await permissionService.refreshPermissions();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('SimulatedPaymentGateway & Checkout', () {
    test('Successful payment upgrades tier and unlocks Semi Premium features reactively', () async {
      expect(featureGate.tier.value, equals(Tier.free));
      expect(featureGate.isEnabled(Feature.stockOpname), isFalse);
      expect(featureGate.isEnabled(Feature.purchases), isFalse);

      final plan = Plan(
        tier: Tier.semi,
        duration: PlanDuration.monthly,
        price: AppConfig.priceSemiMonthly,
      );

      final result = await paymentGateway.pay(plan, paymentMethod: 'qris');

      expect(result.isSuccess, isTrue);
      expect(result.transactionId, isNotNull);

      // FeatureGate reflects new tier reactively without app restart
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.semi));
      expect(featureGate.isEnabled(Feature.stockOpname), isTrue);
      expect(featureGate.isEnabled(Feature.purchases), isTrue);

      // Verify audit log
      final logs = await auditRepo.getAllLogs();
      final tierLog = logs.firstWhere((l) => l.action == AuditActions.licenseTierChanged);
      expect(tierLog.entity, equals('license'));
      expect(tierLog.detail, contains('semi'));
      expect(tierLog.detail, contains('qris'));
    });

    test('Successful payment to Premium unlocks Premium features', () async {
      final plan = Plan(
        tier: Tier.premium,
        duration: PlanDuration.yearly,
        price: AppConfig.pricePremiumYearly,
      );

      final result = await paymentGateway.pay(plan, paymentMethod: 'card');

      expect(result.isSuccess, isTrue);
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.premium));
      expect(featureGate.isEnabled(Feature.hostClient), isTrue);
      expect(featureGate.isEnabled(Feature.teamManagement), isTrue);
    });

    test('Simulated payment failure does not change tier', () async {
      expect(featureGate.tier.value, equals(Tier.free));

      final plan = Plan(
        tier: Tier.premium,
        duration: PlanDuration.monthly,
        price: AppConfig.pricePremiumMonthly,
      );

      final result = await paymentGateway.pay(plan, simulateFailure: true);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, isNotNull);
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.free));
    });

    test('User without license.manage permission is blocked from purchasing', () async {
      // Switch user to cashier
      final cashierUser = await userRepo.getUserByUsername('cashier_test');
      authService.currentUser.value = cashierUser;
      await permissionService.refreshPermissions();

      expect(permissionService.can(PermissionKeys.licenseManage), isFalse);

      final plan = Plan(
        tier: Tier.semi,
        duration: PlanDuration.monthly,
        price: AppConfig.priceSemiMonthly,
      );

      expect(
        () => paymentGateway.pay(plan),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('License Expiration and Downgrade', () {
    test('Simulating expired license downgrades tier to Free automatically', () async {
      // Set to Semi first
      await licenseRepo.setSimulatedTier(Tier.semi, duration: const Duration(days: 30));
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.semi));
      expect(featureGate.isEnabled(Feature.stockOpname), isTrue);

      // Now set expired license
      await licenseRepo.setExpiredLicense(tier: Tier.semi);
      await pumpEventQueue();

      expect(featureGate.tier.value, equals(Tier.free));
      expect(featureGate.isEnabled(Feature.stockOpname), isFalse);
    });

    test('Reset to free restores Free tier and locks features', () async {
      await licenseRepo.setSimulatedTier(Tier.premium, duration: const Duration(days: 30));
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.premium));

      await licenseRepo.resetToFree();
      await pumpEventQueue();
      expect(featureGate.tier.value, equals(Tier.free));
    });
  });

  group('DeveloperPanelController Sample Data Management', () {
    test('Generates 50 products and 50 sales, and only deletes sample data', () async {
      final devController = Get.put(DeveloperPanelController());
      DeveloperPanelController.isUnlocked.value = true;

      // Insert real user product & sale first
      final realProductId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'Produk Riil Pelanggan',
              sellPrice: const Value(25000),
              costPrice: const Value(15000),
            ),
          );

      final realSaleId = await db.into(db.sales).insert(
            SalesCompanion.insert(
              uuid: 'real-sale-uuid-001',
              deviceId: 'pos-main',
              invoiceNo: 'INV-20261020-0001',
              cashierId: 1,
              subtotal: const Value(25000),
              total: const Value(25000),
              paid: const Value(25000),
            ),
          );

      // Generate sample data
      await devController.generateSampleData();
      expect(devController.sampleProductCount.value, equals(50));
      expect(devController.sampleSaleCount.value, equals(50));

      final allProducts = await db.select(db.products).get();
      expect(allProducts.length, equals(51)); // 50 sample + 1 real

      final allSales = await db.select(db.sales).get();
      expect(allSales.length, equals(51)); // 50 sample + 1 real

      // Delete sample data
      await devController.deleteSampleData();
      expect(devController.sampleProductCount.value, equals(0));
      expect(devController.sampleSaleCount.value, equals(0));

      // Verify real data is completely intact!
      final remainingProducts = await db.select(db.products).get();
      expect(remainingProducts.length, equals(1));
      expect(remainingProducts.first.id, equals(realProductId));
      expect(remainingProducts.first.name, equals('Produk Riil Pelanggan'));

      final remainingSales = await db.select(db.sales).get();
      expect(remainingSales.length, equals(1));
      expect(remainingSales.first.id, equals(realSaleId));
      expect(remainingSales.first.invoiceNo, equals('INV-20261020-0001'));
    });

    test('AuditDao returns latest 50 logs correctly', () async {
      final devController = Get.put(DeveloperPanelController());
      DeveloperPanelController.isUnlocked.value = true;

      // Ensure at least one audit log exists
      await auditService.log(
        action: AuditActions.settingsUpdate,
        entity: 'test',
        detail: {'info': 'testing audit log'},
      );

      await devController.loadAuditLogs();
      expect(devController.auditLogs, isNotEmpty);
      expect(devController.auditLogs.length, lessThanOrEqualTo(50));
    });
  });
}
