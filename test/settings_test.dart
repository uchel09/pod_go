import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/audit/audit_actions.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_keys.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/printing/printer_manager.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/theme/theme_service.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/crypto_utils.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/data/services/payment_gateway.dart';
import 'package:pos_me/app/modules/settings/controllers/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late RoleRepository roleRepo;
  late LicenseRepository licenseRepo;
  late AuditRepository auditRepo;
  late StoreRepository storeRepo;
  late SettingsRepository settingsRepo;
  late UserRepository userRepo;
  late SimulatedEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuditService auditService;
  late AuthService authService;
  late ThemeService themeService;
  late PrinterManager printerManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-dev-uuid-16b',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db);

    roleRepo = RoleRepository(db.roleDao);
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);
    storeRepo = StoreRepository(db.storeDao);
    settingsRepo = SettingsRepository(db.settingsDao);
    userRepo = UserRepository(db.userDao);

    Get.put<StoreRepository>(storeRepo);
    Get.put<SettingsRepository>(settingsRepo);
    Get.put<LicenseRepository>(licenseRepo);
    Get.put<PaymentGateway>(SimulatedPaymentGateway(licenseRepo));

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

    themeService = ThemeService();
    await themeService.init();
    Get.put<ThemeService>(themeService);

    printerManager = PrinterManager();
    await printerManager.loadSettings();
    Get.put<PrinterManager>(printerManager);

    // Seed default roles
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final kasirRole = await roleRepo.getRoleByName('Kasir');

    // Buat akun owner dengan PIN '1234'
    final initialPinHash = CryptoUtils.hashSecret('1234');
    final initialRecoveryHash = CryptoUtils.hashSecret(
      CryptoUtils.normalizeCode('ABCD-EFGH-JKLM-NPQR'),
    );

    final ownerUserId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner_settings'),
        displayName: const Value('Owner Settings'),
        pinHash: Value(initialPinHash),
        recoveryCodeHash: Value(initialRecoveryHash),
        roleId: Value(ownerRole!.id),
      ),
    );

    // Buat akun kasir
    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('kasir_settings'),
        displayName: const Value('Kasir Settings'),
        pinHash: Value(CryptoUtils.hashSecret('9999')),
        roleId: Value(kasirRole!.id),
      ),
    );

    // Insert toko mode Solo
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Awal'),
        address: Value('Jl. Merdeka No. 1'),
        phone: Value('08123456789'),
        mode: Value('solo'),
        requireLogin: Value(true),
        scannerType: Value('1d'),
      ),
    );
    await authService.refreshState();

    final ownerUser = await userRepo.getUserById(ownerUserId);
    authService.currentUser.value = ownerUser;
    await permissionService.refreshPermissions();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 16B: Halaman Pengaturan Lengkap Tests', () {
    test('1. Perubahan nama toko tersimpan dan tercatat audit', () async {
      final controller = Get.put(SettingsController());
      await controller.loadAllSettings();

      controller.storeNameController.text = 'Toko Berkah Mandiri Baru';
      controller.storeAddressController.text = 'Jl. Baru No. 45';
      controller.storePhoneController.text = '08987654321';
      controller.receiptFooterController.text = 'Terima Kasih Banyak!';

      await controller.saveStoreProfile();

      // Verifikasi store di database ter-update
      final updatedStore = await storeRepo.getStore();
      expect(updatedStore?.name, equals('Toko Berkah Mandiri Baru'));
      expect(updatedStore?.address, equals('Jl. Baru No. 45'));
      expect(updatedStore?.phone, equals('08987654321'));

      // Verifikasi footer tersimpan di settings
      final footer = await settingsRepo.getSetting('receipt.footer');
      expect(footer, equals('Terima Kasih Banyak!'));

      // Verifikasi tercatat di AuditService
      final logs = await auditRepo.getAllLogs();
      final storeAudit = logs.firstWhere(
        (l) => l.action == AuditActions.settingsUpdate && l.entity == 'stores',
      );
      expect(storeAudit.detail, contains('store_name'));
    });

    test(
      '2. Ganti password memverifikasi password lama dan tidak menyimpan plain text',
      () async {
        final controller = Get.put(SettingsController());

        // Gagal jika password lama salah
        expect(
          () => controller.changePassword(
            oldSecret: 'wrong_pin',
            newSecret: '5678',
            confirmSecret: '5678',
          ),
          throwsA(isA<AppException>()),
        );

        // Berhasil jika password lama benar
        await controller.changePassword(
          oldSecret: '1234',
          newSecret: '5678',
          confirmSecret: '5678',
        );

        // Verifikasi di database: TIDAK ADA plain text '5678'
        final user = await userRepo.getUserByUsername('owner_settings');
        expect(user?.pinHash, isNotNull);
        expect(user?.pinHash, isNot(equals('5678')));
        expect(user?.pinHash!.startsWith(r'$2'), isTrue); // Format bcrypt hash
        expect(CryptoUtils.verifySecret('5678', user!.pinHash!), isTrue);

        // Verifikasi audit log tercatat
        final logs = await auditRepo.getAllLogs();
        final passAudit = logs.firstWhere(
          (l) => l.action == AuditActions.authPasswordChanged,
        );
        expect(passAudit.entity, equals('users'));
        expect(
          passAudit.detail,
          isNull,
        ); // Tidak ada bocoran password/hash di log
      },
    );

    test(
      '3. Menonaktifkan login Solo butuh verifikasi secret saat ini',
      () async {
        final controller = Get.put(SettingsController());

        // Gagal jika verifikasi secret salah
        expect(
          () => controller.deactivateSoloLogin('wrong_secret'),
          throwsA(isA<AppException>()),
        );

        // Login masih tetap aktif
        var store = await storeRepo.getStore();
        expect(store?.requireLogin, isTrue);

        // Berhasil jika secret benar ('1234')
        await controller.deactivateSoloLogin('1234');

        store = await storeRepo.getStore();
        expect(store?.requireLogin, isFalse);

        // Audit log tercatat
        final logs = await auditRepo.getAllLogs();
        final soloAudit = logs.firstWhere(
          (l) =>
              l.action == AuditActions.settingsUpdate &&
              l.entity == 'stores' &&
              l.detail != null &&
              l.detail!.contains('require_login'),
        );
        expect(soloAudit.detail, contains('false'));
      },
    );

    test(
      '4. Role tanpa settings.manage ditolak di repository (Store & Settings)',
      () async {
        // Ubah store ke mode Tim agar RBAC berlaku ketat
        final store = await storeRepo.getStore();
        await db.update(db.stores).replace(store!.copyWith(mode: 'team'));
        await authService.refreshState();

        // Ganti user aktif ke Kasir (tidak punya settings.manage)
        final cashier = await userRepo.getUserByUsername('kasir_settings');
        authService.currentUser.value = cashier;
        await permissionService.refreshPermissions();

        expect(permissionService.can(PermissionKeys.settingsManage), isFalse);

        // StoreRepository.updateStore melempar FORBIDDEN
        expect(
          () => storeRepo.updateStore(
            store.toCompanion(true).copyWith(name: const Value('Toko Ilegal')),
          ),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN'),
          ),
        );

        // SettingsRepository.setSetting untuk kunci sensitif melempar FORBIDDEN
        expect(
          () => settingsRepo.setSetting('pos.allow_negative_stock', 'true'),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN'),
          ),
        );

        expect(
          () => settingsRepo.setSetting('receipt_footer', 'Footer Ilegal'),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN'),
          ),
        );

        // Ganti kembali ke Owner -> diizinkan
        final owner = await userRepo.getUserByUsername('owner_settings');
        authService.currentUser.value = owner;
        await permissionService.refreshPermissions();

        expect(permissionService.can(PermissionKeys.settingsManage), isTrue);
        await storeRepo.updateStore(
          store.toCompanion(true).copyWith(name: const Value('Toko Legal')),
        );
        final finalStore = await storeRepo.getStore();
        expect(finalStore?.name, equals('Toko Legal'));
      },
    );

    test('5. Lebar struk sinkron dengan Pengaturan Printer', () async {
      final controller = Get.put(SettingsController());
      await controller.loadAllSettings();

      expect(controller.paperWidth.value, equals('58'));
      expect(printerManager.paperWidth.value, equals('58'));

      // Ubah ke 80mm
      controller.paperWidth.value = '80';
      await controller.saveSalesSettings();

      // Sinkron ke settings database
      expect(
        await settingsRepo.getSetting(PrinterManager.keyPaperWidth),
        equals('80'),
      );
      expect(await settingsRepo.getSetting('pos.receipt_width'), equals('80'));

      // Sinkron ke PrinterManager
      expect(printerManager.paperWidth.value, equals('80'));
      expect(printerManager.charsPerLine.value, equals(48));

      // Verifikasi audit log
      final logs = await auditRepo.getAllLogs();
      final audit = logs.firstWhere(
        (l) =>
            l.action == AuditActions.settingsUpdate &&
            l.entity == 'settings' &&
            l.detail != null &&
            l.detail!.contains('printer.paper_width'),
      );
      expect(audit, isNotNull);
    });

    test(
      '6. Tampilan tema dan warna utama tersimpan di ThemeService',
      () async {
        final controller = Get.put(SettingsController());

        // Ganti tema ke Gelap
        await controller.setThemeMode(ThemeMode.dark);
        expect(themeService.themeMode, equals(ThemeMode.dark));
        expect(themeService.isDarkMode, isTrue);

        // Ganti warna utama
        const emeraldColor = Color(0xFF00796B);
        await controller.setPrimaryColor(emeraldColor);
        expect(
          themeService.primaryColor.toARGB32(),
          equals(emeraldColor.toARGB32()),
        );
      },
    );

    test(
      '7. Rotasi Recovery Code menyimpan hash aman tanpa bocoran secret di log',
      () async {
        final controller = Get.put(SettingsController());
        const newCode = '9876-5432-ABCD-EFGH';

        await controller.saveRotatedRecoveryCode(newCode);

        final user = await userRepo.getUserByUsername('owner_settings');
        expect(user?.recoveryCodeHash, isNotNull);
        expect(user?.recoveryCodeHash, isNot(contains('9876')));
        expect(user?.recoveryCodeHash!.startsWith(r'$2'), isTrue);

        // Verifikasi hash cocok dengan normalisasi
        expect(
          CryptoUtils.verifySecret('98765432ABCDEFGH', user!.recoveryCodeHash!),
          isTrue,
        );

        // Verifikasi audit log tidak memuat recovery code
        final logs = await auditRepo.getAllLogs();
        final rotAudit = logs.firstWhere(
          (l) =>
              l.action == AuditActions.settingsUpdate &&
              l.entity == 'users' &&
              l.detail != null &&
              l.detail!.contains('rotate_recovery_code'),
        );
        expect(rotAudit.detail, isNot(contains(newCode)));
      },
    );
  });
}
