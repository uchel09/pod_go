import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/sale_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late ProductRepository productRepo;
  late StockRepository stockRepo;
  late SaleRepository saleRepo;
  late ReportRepository reportRepo;
  late LicenseRepository licenseRepo;
  late SettingsRepository settingsRepo;
  late AuditRepository auditRepo;
  late User testUser;
  late Product testProduct;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-tax-dev-001',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    settingsRepo = SettingsRepository(db.settingsDao);
    stockRepo = StockRepository(db, db.stockDao, db.productDao);
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao);
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);

    final reportDao = ReportDao(db);
    reportRepo = ReportRepository(reportDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);
    Get.put<ProductRepository>(productRepo, permanent: true);
    Get.put<StockRepository>(stockRepo, permanent: true);
    Get.put<SaleRepository>(saleRepo, permanent: true);
    Get.put<ReportRepository>(reportRepo, permanent: true);
    Get.put<LicenseRepository>(licenseRepo, permanent: true);
    Get.put<AuditRepository>(auditRepo, permanent: true);
    Get.put<SettingsRepository>(settingsRepo, permanent: true);

    final entitlementProvider = SimulatedEntitlementProvider(licenseRepo);
    final featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate, permanent: true);

    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService, permanent: true);

    final permService = PermissionService(roleRepo);
    await permService.init();
    Get.put<PermissionService>(permService, permanent: true);

    final authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    // Setup toko dan user
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Pajak Makmur'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );

    final ownerRole = await roleRepo.getRoleByName('Owner');
    final userId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Pemilik Toko'),
        roleId: Value(ownerRole!.id),
      ),
    );
    testUser = (await userRepo.getUserById(userId))!;

    // Tambah produk untuk tes
    final pId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Barang Kena Pajak'),
        sellPrice: Value(100000),
        costPrice: Value(60000),
        currentStock: Value(50),
        isActive: Value(true),
      ),
    );
    testProduct = (await productRepo.getProductById(pId))!;
    await AuthService.to.init();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Tax Integration & Checkout Tests', () {
    test('Simpan dan baca pengaturan pajak di SettingsRepository', () async {
      await settingsRepo.setSetting('tax.enabled', 'true');
      await settingsRepo.setSetting('tax.name', 'PPN');
      await settingsRepo.setSetting('tax.rate_bps', '1100');
      await settingsRepo.setSetting('tax.mode', 'exclusive');

      expect(await settingsRepo.getSetting('tax.enabled'), equals('true'));
      expect(await settingsRepo.getSetting('tax.name'), equals('PPN'));
      expect(await settingsRepo.getSetting('tax.rate_bps'), equals('1100'));
      expect(await settingsRepo.getSetting('tax.mode'), equals('exclusive'));
    });

    test('Checkout kasir dengan pajak eksklusif 11%: Subtotal 100k + PPN 11k = Total 111k', () async {
      final items = [
        CheckoutCartItem(
          productId: testProduct.id,
          productName: testProduct.name,
          qty: 1,
          price: 100000,
          costPrice: 60000,
        ),
      ];

      final payments = [
        const CheckoutPayment(method: 'cash', amount: 120000),
      ];

      final result = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'test-device-01',
        items: items,
        payments: payments,
        tax: 11000,
        taxRateBps: 1100,
        taxMode: 'exclusive',
      );

      final sale = result.sale;
      expect(sale.subtotal, equals(100000));
      expect(sale.tax, equals(11000));
      expect(sale.taxRateBps, equals(1100));
      expect(sale.taxMode, equals('exclusive'));
      expect(sale.total, equals(111000));
      expect(sale.paid, equals(120000));
      expect(sale.change, equals(9000));
    });

    test('Checkout kasir dengan pajak inklusif 11%: Total tetap 111k, Pajak 11k tersimpan', () async {
      final items = [
        CheckoutCartItem(
          productId: testProduct.id,
          productName: testProduct.name,
          qty: 1,
          price: 111000,
          costPrice: 60000,
        ),
      ];

      final payments = [
        const CheckoutPayment(method: 'cash', amount: 111000),
      ];

      final result = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'test-device-01',
        items: items,
        payments: payments,
        tax: 11000,
        taxRateBps: 1100,
        taxMode: 'inclusive',
      );

      final sale = result.sale;
      expect(sale.subtotal, equals(111000));
      expect(sale.tax, equals(11000));
      expect(sale.taxRateBps, equals(1100));
      expect(sale.taxMode, equals('inclusive'));
      expect(sale.total, equals(111000));
      expect(sale.change, equals(0));
    });

    test('Immutabilitas riwayat: perubahan setting pajak di masa depan tidak mengubah transaksi lama', () async {
      // 1. Transaksi saat tarif 11%
      final res1 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'test-device-01',
        items: [
          CheckoutCartItem(
            productId: testProduct.id,
            productName: testProduct.name,
            qty: 1,
            price: 100000,
            costPrice: 60000,
          ),
        ],
        payments: [const CheckoutPayment(method: 'cash', amount: 111000)],
        tax: 11000,
        taxRateBps: 1100,
        taxMode: 'exclusive',
      );

      // 2. Setting diubah ke 12% (1200 bps)
      await settingsRepo.setSetting('tax.rate_bps', '1200');

      // 3. Baca detail transaksi lama dari DB
      final savedOldSale = await saleRepo.getSaleById(res1.sale.id);
      expect(savedOldSale, isNotNull);
      expect(savedOldSale!.tax, equals(11000));
      expect(savedOldSale.taxRateBps, equals(1100));
      expect(savedOldSale.taxMode, equals('exclusive'));
      expect(savedOldSale.total, equals(111000));
    });

    test('Laporan keuangan menghitung Pendapatan Bersih = Omzet - Pajak dan Laba = Bersih - HPP', () async {
      await licenseRepo.setSimulatedTier(Tier.semi);
      FeatureGate.to.tier.value = Tier.semi;

      final now = DateTime.now();
      // Checkout transaksi 1: Omzet 111.000, Pajak 11.000, HPP 60.000
      await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'test-device-01',
        items: [
          CheckoutCartItem(
            productId: testProduct.id,
            productName: testProduct.name,
            qty: 1,
            price: 100000,
            costPrice: 60000,
          ),
        ],
        payments: [const CheckoutPayment(method: 'cash', amount: 111000)],
        tax: 11000,
        taxRateBps: 1100,
        taxMode: 'exclusive',
        transactionTime: now,
      );

      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 1));
      final fullReport = await reportRepo.getFullReport(from: from, to: to);

      expect(fullReport.summary.omzet, equals(111000));
      expect(fullReport.summary.tax, equals(11000));
      expect(fullReport.summary.netRevenue, equals(100000)); // 111k - 11k
      expect(fullReport.summary.cogs, equals(60000));
      expect(fullReport.summary.grossProfit, equals(40000)); // 100k - 60k
    });
  });
}

