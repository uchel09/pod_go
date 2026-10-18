import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/feature_enum.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_keys.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-device-uuid-999',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    roleRepo = RoleRepository(db.roleDao);
    licenseRepo = LicenseRepository(db.licenseDao);
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
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('RoleSeeder & RBAC Tests', () {
    test('RoleSeeder idempotent: seeder tepat sekali meski dipanggil berulang', () async {
      // 1. Eksekusi pertama
      await RoleSeeder.seedDefaultRoles(roleRepo);
      final rolesFirst = await roleRepo.getAllRoles();
      expect(rolesFirst.length, 5); // Owner, Admin, Kasir, Gudang, Crew

      final ownerRole = await roleRepo.getRoleByName('Owner');
      expect(ownerRole, isNotNull);
      expect(ownerRole!.isLocked, isTrue);
      expect(ownerRole.isSystem, isTrue);

      final ownerPerms = await roleRepo.getPermissionsByRole(ownerRole.id);
      expect(ownerPerms.length, PermissionKeys.all.length);

      // 2. Eksekusi kedua (harus idempotent tanpa duplikasi)
      await RoleSeeder.seedDefaultRoles(roleRepo);
      final rolesSecond = await roleRepo.getAllRoles();
      expect(rolesSecond.length, 5);

      final ownerPermsSecond = await roleRepo.getPermissionsByRole(ownerRole.id);
      expect(ownerPermsSecond.length, PermissionKeys.all.length);
    });

    test('Permission per Role: Crew tidak bisa pos.sell, Kasir bisa pos.sell', () async {
      await RoleSeeder.seedDefaultRoles(roleRepo);

      // Setup store dalam mode Tim agar pengecekan izin role aktif
      await storeRepo.insertStore(
        const StoresCompanion(
          name: Value('Toko Tim Bersama'),
          mode: Value('team'),
          requireLogin: Value(true),
        ),
      );
      await authService.refreshState();

      final crewRole = await roleRepo.getRoleByName('Crew');
      final kasirRole = await roleRepo.getRoleByName('Kasir');

      // 1. Login sebagai Crew
      final crewUserId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('staf_crew'),
          displayName: const Value('Staf Crew'),
          roleId: Value(crewRole!.id),
        ),
      );
      final crewUser = await userRepo.getUserById(crewUserId);
      authService.currentUser.value = crewUser;
      await permissionService.refreshPermissions();

      // Verifikasi hak akses Crew:
      // role Crew -> can('pos.sell') false
      expect(permissionService.can(PermissionKeys.posSell), isFalse);
      expect(permissionService.can(PermissionKeys.productView), isTrue);
      expect(permissionService.can(PermissionKeys.stockView), isTrue);
      expect(permissionService.can(PermissionKeys.attendanceSelf), isTrue);
      expect(permissionService.can(PermissionKeys.productViewCost), isFalse);

      // 2. Login sebagai Kasir
      final kasirUserId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('kasir_utama'),
          displayName: const Value('Kasir Utama'),
          roleId: Value(kasirRole!.id),
        ),
      );
      final kasirUser = await userRepo.getUserById(kasirUserId);
      authService.currentUser.value = kasirUser;
      await permissionService.refreshPermissions();

      // Verifikasi hak akses Kasir:
      expect(permissionService.can(PermissionKeys.posSell), isTrue);
      expect(permissionService.can(PermissionKeys.posDiscount), isTrue);
      expect(permissionService.can(PermissionKeys.productEdit), isFalse);
    });

    test('Mode Solo dengan Owner: can() selalu true untuk semua izin', () async {
      await RoleSeeder.seedDefaultRoles(roleRepo);

      await storeRepo.insertStore(
        const StoresCompanion(
          name: Value('Warung Solo'),
          mode: Value('solo'),
          requireLogin: Value(false),
        ),
      );
      final ownerRole = await roleRepo.getRoleByName('Owner');
      final ownerId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('owner_solo'),
          displayName: const Value('Owner Solo'),
          roleId: Value(ownerRole!.id),
        ),
      );
      authService.currentUser.value = await userRepo.getUserById(ownerId);
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(permissionService.can(PermissionKeys.posSell), isTrue);
      expect(permissionService.can(PermissionKeys.settingsManage), isTrue);
      expect(permissionService.can('apa_saja_diizinkan'), isTrue);
    });
  });

  group('FeatureGate & Entitlement Simulasi Tests', () {
    test('Tier Gratis: isEnabled(Feature.stockOpname) false & limit 10 produk', () async {
      // Tanpa lisensi terdaftar -> Default Gratis
      expect(featureGate.tier.value, Tier.free);
      expect(featureGate.isEnabled(Feature.stockOpname), isFalse);
      expect(featureGate.isEnabled(Feature.unlimitedProducts), isFalse);
      expect(featureGate.isEnabled(Feature.teamManagement), isFalse);
      expect(featureGate.productLimit, 10);
    });

    test('Mengganti baris licenses ke semi mengubah isEnabled secara real-time via stream', () async {
      expect(featureGate.isEnabled(Feature.stockOpname), isFalse);

      // Simulasikan aktivasi lisensi Semi Premium
      await licenseRepo.insertLicense(
        const LicensesCompanion(
          tier: Value('semi'),
          source: Value('simulated'),
          status: Value('active'),
        ),
      );

      // Tunggu stream memproses emisi baru
      await pumpEventQueue();

      expect(featureGate.tier.value, Tier.semi);
      // tier Semi -> isEnabled(Feature.stockOpname) true
      expect(featureGate.isEnabled(Feature.stockOpname), isTrue);
      expect(featureGate.isEnabled(Feature.unlimitedProducts), isTrue);
      expect(featureGate.isEnabled(Feature.purchases), isTrue);
      expect(featureGate.isEnabled(Feature.importExport), isTrue);
      expect(featureGate.isEnabled(Feature.fullReports), isTrue);
      expect(featureGate.isEnabled(Feature.autoBackup), isTrue);
      expect(featureGate.productLimit, isNull);

      // Fitur Tim tetap false di Semi Premium
      expect(featureGate.isEnabled(Feature.teamManagement), isFalse);
      expect(featureGate.isEnabled(Feature.attendance), isFalse);

      // Upgrade ke Premium
      await licenseRepo.insertLicense(
        const LicensesCompanion(
          tier: Value('premium'),
          source: Value('simulated'),
          status: Value('active'),
        ),
      );

      await pumpEventQueue();

      expect(featureGate.tier.value, Tier.premium);
      expect(featureGate.isEnabled(Feature.teamManagement), isTrue);
      expect(featureGate.isEnabled(Feature.attendance), isTrue);
      expect(featureGate.isEnabled(Feature.customRoles), isTrue);
    });

    test('Lisensi yang kedaluwarsa otomatis turun kembali ke Tier Gratis', () async {
      // Buat lisensi Semi yang sudah kedaluwarsa kemarin
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await licenseRepo.insertLicense(
        LicensesCompanion(
          tier: const Value('semi'),
          source: const Value('simulated'),
          status: const Value('active'),
          expiresAt: Value(yesterday),
        ),
      );

      await pumpEventQueue();

      expect(featureGate.tier.value, Tier.free);
      expect(featureGate.isEnabled(Feature.stockOpname), isFalse);
      expect(featureGate.productLimit, 10);
    });
  });

  group('AuditService Tests', () {
    test('AuditService mencatat aktivitas dengan userId dan deviceId secara benar', () async {
      await auditService.log(
        action: 'product.price_changed',
        entity: 'products',
        entityId: 101,
        detail: {'oldPrice': 10000, 'newPrice': 12500},
        overrideUserId: 5,
      );

      final logs = await auditService.getAllLogs();
      expect(logs.length, 1);
      final log = logs.first;
      expect(log.action, 'product.price_changed');
      expect(log.entity, 'products');
      expect(log.entityId, 101);
      expect(log.userId, 5);
      expect(log.deviceId, 'test-device-uuid-999');
      expect(log.detail, contains('12500'));
    });
  });
}
