import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/audit/audit_actions.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/audit_dao.dart';
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/settings_dao.dart';
import 'package:pos_me/app/data/local/daos/store_dao.dart';
import 'package:pos_me/app/data/local/daos/user_dao.dart';
import 'package:pos_me/app/data/models/backup_models.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/backup_repository.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/modules/dashboard/controllers/dashboard_controller.dart';

class MockEntitlementProvider implements EntitlementProvider {
  Tier currentMockTier;
  MockEntitlementProvider(this.currentMockTier);

  @override
  Future<Tier> currentTier() async => currentMockTier;

  @override
  Stream<Tier> watchTier() => Stream.value(currentMockTier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StoreDao storeDao;
  late SettingsDao settingsDao;
  late UserDao userDao;
  late RoleDao roleDao;
  late AuditDao auditDao;

  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late AuditRepository auditRepo;
  late BackupRepository backupRepo;

  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuthService authService;

  late User ownerUser;
  late User cashierUser;
  final List<File> filesToCleanup = [];
  final List<Directory> dirsToCleanup = [];

  setUp(() async {
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    storeDao = db.storeDao;
    settingsDao = db.settingsDao;
    userDao = db.userDao;
    roleDao = db.roleDao;
    auditDao = db.auditDao;

    storeRepo = StoreRepository(storeDao);
    userRepo = UserRepository(userDao);
    roleRepo = RoleRepository(roleDao);
    auditRepo = AuditRepository(auditDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);
    Get.put<AuditRepository>(auditRepo, permanent: true);

    // Seed roles
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final roles = await roleRepo.getAllRoles();
    final ownerRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'owner').id;
    final cashierRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'kasir').id;

    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko Sukses Makmur'),
        mode: drift.Value('team'),
        requireLogin: drift.Value(true),
      ),
    );

    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('owner_test'),
        displayName: const drift.Value('Owner User'),
        roleId: drift.Value(ownerRoleId),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    final cashierId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('cashier_test'),
        displayName: const drift.Value('Cashier User'),
        roleId: drift.Value(cashierRoleId),
      ),
    );
    cashierUser = (await userRepo.getUserById(cashierId))!;

    entitlementProvider = MockEntitlementProvider(Tier.free); // Available on all tiers for manual!
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    permissionService = PermissionService(roleRepo);
    authService = AuthService(storeRepo, userRepo);
    await authService.init();

    Get.put<EntitlementProvider>(entitlementProvider, permanent: true);
    Get.put<FeatureGate>(featureGate, permanent: true);
    Get.put<PermissionService>(permissionService, permanent: true);
    Get.put<AuthService>(authService, permanent: true);
    Get.put<AuditService>(AuditService(auditRepo), permanent: true);

    backupRepo = BackupRepository(
      db: db,
      storeDao: storeDao,
      settingsDao: settingsDao,
    );
    Get.put<BackupRepository>(backupRepo, permanent: true);

    final reportDao = ReportDao(db);
    Get.put<ReportDao>(reportDao, permanent: true);
    Get.put<ReportRepository>(ReportRepository(reportDao), permanent: true);

    // Default: login as owner
    authService.currentUser.value = ownerUser;
    await authService.refreshState();
    await permissionService.refreshPermissions();
  });

  tearDown(() async {
    for (final f in filesToCleanup) {
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    filesToCleanup.clear();

    for (final d in dirsToCleanup) {
      if (await d.exists()) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
    dirsToCleanup.clear();

    await db.close();
    Get.reset();
  });

  group('Prompt 15A & 15B: Backup, Restore & Auto-Backup Tests', () {
    test('createBackup menghasilkan file zip valid berisi database sqlite dan metadata.json', () async {
      await db.customStatement(
        "INSERT INTO products (name, cost_price, sell_price, current_stock, is_active, created_at, updated_at) VALUES ('Kopi Susu', 5000, 10000, 20, 1, '2026-01-01', '2026-01-01')",
      );
      await db.customStatement(
        "INSERT INTO products (name, cost_price, sell_price, current_stock, is_active, created_at, updated_at) VALUES ('Roti Bakar', 8000, 15000, 10, 1, '2026-01-01', '2026-01-01')",
      );
      await db.customStatement(
        "INSERT INTO sales (uuid, device_id, invoice_no, cashier_id, subtotal, discount, tax, total, paid, change, status, created_at) VALUES ('uuid-1', 'dev-1', 'INV-001', 1, 25000, 0, 0, 25000, 30000, 5000, 'completed', '2026-01-01')",
      );

      final result = await backupRepo.createBackup();
      filesToCleanup.add(File(result.filePath));

      expect(result.fileName, startsWith('backup_toko_sukses_makmur_'));
      expect(result.fileName, endsWith('.zip'));
      expect(result.fileSize, greaterThan(0));
      expect(result.bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(result.bytes);
      expect(archive.files.length, 2);

      final dbEntry = archive.findFile('pos_me.db');
      expect(dbEntry, isNotNull);
      final metaEntry = archive.findFile('metadata.json');
      expect(metaEntry, isNotNull);

      final dbBytes = dbEntry!.content as List<int>;
      final headerStr = String.fromCharCodes(dbBytes.take(15));
      expect(headerStr, 'SQLite format 3');

      final metaString = utf8.decode(metaEntry!.content as List<int>);
      final metaMap = jsonDecode(metaString) as Map<String, dynamic>;
      expect(metaMap['schemaVersion'], db.schemaVersion);
      expect(metaMap['storeName'], 'Toko Sukses Makmur');
      expect(metaMap['productCount'], 2);
      expect(metaMap['transactionCount'], 1);

      final logs = await auditDao.getAllLogs();
      expect(logs.any((l) => l.action == AuditActions.backupCreate), isTrue);
    });

    test('Status backup terakhir tersimpan di app_settings dan dapat dibaca oleh getLastBackupInfo', () async {
      final beforeInfo = await backupRepo.getLastBackupInfo();
      expect(beforeInfo, isNull);

      final result = await backupRepo.createBackup();
      filesToCleanup.add(File(result.filePath));

      final afterInfo = await backupRepo.getLastBackupInfo();
      expect(afterInfo, isNotNull);
      expect(afterInfo!.sizeInBytes, result.fileSize);
      expect(afterInfo.fileName, result.fileName);
      expect(afterInfo.daysAgo, 0);
      expect(afterInfo.formattedSize, isNotEmpty);
    });

    test('User tanpa izin backup.manage ditolak dengan kode FORBIDDEN', () async {
      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(
        () => backupRepo.createBackup(),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', 'FORBIDDEN')
              .having((e) => e.message, 'message', contains('backup.manage')),
        ),
      );
    });

    test('Pengingat backup di DashboardController: muncul jika belum pernah atau > 7 hari', () async {
      final dashboardCtrl = Get.put<DashboardController>(DashboardController());
      await dashboardCtrl.loadDashboard();
      expect(dashboardCtrl.shouldShowBackupReminder, isTrue);

      final result = await backupRepo.createBackup();
      filesToCleanup.add(File(result.filePath));

      await dashboardCtrl.refreshDashboard();
      expect(dashboardCtrl.shouldShowBackupReminder, isFalse);

      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10)).toIso8601String();
      await settingsDao.setSetting('last_backup_at', tenDaysAgo);

      await dashboardCtrl.refreshDashboard();
      expect(dashboardCtrl.shouldShowBackupReminder, isTrue);
      expect(dashboardCtrl.backupDaysAgo, greaterThanOrEqualTo(10));

      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();
      expect(dashboardCtrl.shouldShowBackupReminder, isFalse);
    });

    // =======================================================================
    // PENGUJIAN PROMPT 15B: RESTORE & AUTO-BACKUP
    // =======================================================================

    test('Backup lalu restore menghasilkan data identik pada target database', () async {
      // 1. Simpan data awal yang valid
      await db.customStatement(
        "INSERT INTO products (name, cost_price, sell_price, current_stock, is_active) VALUES ('Kopi Spesial Asli', 7000, 15000, 50, 1)",
      );

      // 2. Buat backup dari database awal
      final backupResult = await backupRepo.createBackup();
      final backupFile = File(backupResult.filePath);
      filesToCleanup.add(backupFile);

      // 3. Siapkan file target tiruan untuk menguji penimpaan restore
      final testTargetDb = File('${Directory.systemTemp.path}/test_target_restore_${DateTime.now().microsecondsSinceEpoch}.sqlite');
      filesToCleanup.add(testTargetDb);

      // Tulis kondisi berbeda di file target (misal data berubah sebelum restore)
      final dummyDb = AppDatabase(NativeDatabase(testTargetDb));
      await dummyDb.customStatement(
        "INSERT INTO products (name, cost_price, sell_price, current_stock, is_active) VALUES ('Produk Sementara Yang Salah', 1000, 2000, 1, 1)",
      );
      await dummyDb.close();

      // 4. Validasi berkas backup
      final preview = await backupRepo.validateBackupForRestore(backupFile);
      expect(preview.backupMetadata.storeName, 'Toko Sukses Makmur');
      expect(preview.backupMetadata.schemaVersion, db.schemaVersion);

      // 5. Eksekusi restore ke target file
      await backupRepo.executeRestore(preview, customTargetDbFile: testTargetDb);

      // 6. Buka kembali file target yang telah direstore dan verifikasi datanya identik
      final restoredTargetDb = AppDatabase(NativeDatabase(testTargetDb));
      final products = await restoredTargetDb.productDao.getAllProducts();
      await restoredTargetDb.close();

      expect(products.any((p) => p.name == 'Kopi Spesial Asli'), isTrue);
      expect(products.any((p) => p.name == 'Produk Sementara Yang Salah'), isFalse);
    });

    test('Berkas ZIP rusak ditolak dengan kode CORRUPTED_ZIP', () async {
      final corruptFile = File('${Directory.systemTemp.path}/corrupt_test_${DateTime.now().microsecondsSinceEpoch}.zip');
      filesToCleanup.add(corruptFile);
      await corruptFile.writeAsBytes([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);

      expect(
        () => backupRepo.validateBackupForRestore(corruptFile),
        throwsA(
          isA<AppException>().having((e) => e.code, 'code', 'CORRUPTED_ZIP'),
        ),
      );
    });

    test('Backup dengan schemaVersion lebih tinggi dari aplikasi ditolak (SCHEMA_TOO_NEW)', () async {
      final futureMeta = BackupMetadata(
        schemaVersion: 99, // Lebih tinggi dari app (v2)
        appVersion: '2.5.0',
        timestamp: DateTime.now().toIso8601String(),
        storeName: 'Toko Masa Depan',
        productCount: 10,
        transactionCount: 5,
      );

      final archive = Archive();
      archive.addFile(ArchiveFile('pos_me.db', 10, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
      final metaBytes = utf8.encode(jsonEncode(futureMeta.toJson()));
      archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

      final zipBytes = ZipEncoder().encode(archive)!;
      final futureZip = File('${Directory.systemTemp.path}/future_schema_${DateTime.now().microsecondsSinceEpoch}.zip');
      filesToCleanup.add(futureZip);
      await futureZip.writeAsBytes(zipBytes);

      expect(
        () => backupRepo.validateBackupForRestore(futureZip),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', 'SCHEMA_TOO_NEW')
              .having((e) => e.message, 'message', contains('lebih baru')),
        ),
      );
    });

    test('Restore gagal di tengah jalan tidak merusak data lama (fail-safe rollback)', () async {
      final targetFile = File('${Directory.systemTemp.path}/rollback_test_${DateTime.now().microsecondsSinceEpoch}.sqlite');
      filesToCleanup.add(targetFile);
      await targetFile.writeAsString('DATABASE_LAMA_YANG_BERHARGA');

      // Siapkan preview palsu dengan path berkas hasil ekstraksi yang tidak ada
      final invalidPreview = RestorePreview(
        fileName: 'invalid.zip',
        fileSize: 100,
        backupMetadata: BackupMetadata(
          schemaVersion: db.schemaVersion,
          appVersion: '1.0.0',
          timestamp: '2026-01-01',
          storeName: 'Test',
          productCount: 0,
          transactionCount: 0,
        ),
        currentStoreName: 'Toko Sukses Makmur',
        currentProductCount: 0,
        currentTransactionCount: 0,
        currentDate: DateTime.now(),
        tempExtractedDbPath: '${Directory.systemTemp.path}/non_existent_file.db',
        rawZipBytes: Uint8List(0),
      );

      expect(
        () => backupRepo.executeRestore(invalidPreview, customTargetDbFile: targetFile),
        throwsA(
          isA<AppException>().having((e) => e.code, 'code', 'RESTORE_FAILED'),
        ),
      );

      // Data lama harus tetap utuh dan tidak rusak
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsString(), 'DATABASE_LAMA_YANG_BERHARGA');
    });

    test('Rotasi auto-backup menyisakan tepat N berkas terbaru', () async {
      final autoFolder = Directory('${Directory.systemTemp.path}/auto_backup_test_${DateTime.now().microsecondsSinceEpoch}');
      await autoFolder.create();
      dirsToCleanup.add(autoFolder);

      // Buat 5 berkas backup tiruan
      for (int i = 1; i <= 5; i++) {
        final f = File('${autoFolder.path}/backup_test_$i.zip');
        await f.writeAsString('content $i');
        // Jeda waktu sedikit agar timestamp modified berbeda
        await Future.delayed(const Duration(milliseconds: 20));
      }

      var files = autoFolder.listSync().whereType<File>().toList();
      expect(files.length, 5);

      // Jalankan rotasi agar hanya tersisa 3 file terbaru
      await backupRepo.rotateBackups(autoFolder, 3);

      files = autoFolder.listSync().whereType<File>().toList();
      expect(files.length, 3);
    });

    test('Tier Gratis ditolak untuk auto-backup (FEATURE_LOCKED)', () async {
      final autoFolder = Directory('${Directory.systemTemp.path}/auto_tier_test_${DateTime.now().microsecondsSinceEpoch}');
      await autoFolder.create();
      dirsToCleanup.add(autoFolder);

      // Di tier Free:
      entitlementProvider.currentMockTier = Tier.free;
      await featureGate.init();

      expect(
        () => backupRepo.testAutoBackup(folderPath: autoFolder.path),
        throwsA(
          isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED'),
        ),
      );

      // Di tier Semi-Premium:
      entitlementProvider.currentMockTier = Tier.semi;
      await featureGate.init();

      final result = await backupRepo.testAutoBackup(folderPath: autoFolder.path);
      filesToCleanup.add(File(result.filePath));
      expect(result.fileSize, greaterThan(0));
    });
  });
}
