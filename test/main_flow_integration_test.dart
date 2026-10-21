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
import 'package:pos_me/app/data/services/payment_gateway.dart';
import 'package:pos_me/app/modules/developer_panel/controllers/developer_panel_controller.dart';
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
  late AuditRepository auditRepo;
  late SettingsRepository settingsRepo;
  late DeveloperPanelController devController;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-integration-dev-001',
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

    Get.put<PaymentGateway>(SimulatedPaymentGateway(licenseRepo), permanent: true);

    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService, permanent: true);

    final permService = PermissionService(roleRepo);
    await permService.init();
    Get.put<PermissionService>(permService, permanent: true);

    final authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Beras Berkah'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );

    final ownerRole = await roleRepo.getRoleByName('Owner');
    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner_pos'),
        displayName: const Value('Budi Santoso'),
        roleId: Value(ownerRole!.id),
      ),
    );

    await AuthService.to.init();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 17: Main Flow Integration Test', () {
    test('Alur Penuh: Setup Toko -> Tambah Produk -> Jual -> Void -> Cek Stok & Laporan', () async {
      final ownerId = AuthService.to.currentUser.value!.id;

      // 2. TAMBAH MASTER PRODUK DENGAN STOK AWAL
      final productId = await productRepo.createProduct(
        const ProductsCompanion(
          name: Value('Beras Ramos 5kg'),
          barcode: Value('8991234567890'),
          sku: Value('SKU-BRS-5K'),
          costPrice: Value(50000),
          sellPrice: Value(65000),
          minStock: Value(5),
          isActive: Value(true),
        ),
      );

      // Stok awal 20 unit dicatat melalui StockRepository.applyMovement
      await stockRepo.applyMovement(
        productId: productId,
        type: 'adjustment',
        qtyChange: 20,
        refTable: 'products',
        refId: productId,
        note: 'Stok awal setup',
      );

      var productAfterSetup = await productRepo.getProductById(productId);
      expect(productAfterSetup?.currentStock, 20);

      // 3. JUAL (CHECKOUT KASIR: 2 UNIT)
      final checkoutResult = await saleRepo.checkout(
        cashierId: ownerId,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: productId,
            productName: 'Beras Ramos 5kg',
            qty: 2,
            price: 65000,
            costPrice: 50000,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 150000),
        ],
      );

      expect(checkoutResult.sale.total, 130000);
      expect(checkoutResult.sale.change, 20000);
      expect(checkoutResult.sale.status, 'completed');

      // Verifikasi stok berkurang ke 18
      var productAfterSale = await productRepo.getProductById(productId);
      expect(productAfterSale?.currentStock, 18);

      // Verifikasi snapshot pada sale_items tidak akan terpengaruh jika harga master diedit
      final saleItems = await saleRepo.getItemsBySaleId(checkoutResult.sale.id);
      expect(saleItems.length, 1);
      expect(saleItems.first.qty, 2);
      expect(saleItems.first.price, 65000);
      expect(saleItems.first.costPrice, 50000);

      // Dashboard hari ini mencatat omzet 130.000
      var dashboardBeforeVoid = await reportRepo.getDashboardData();
      expect(dashboardBeforeVoid.todayOmzet, 130000);
      expect(dashboardBeforeVoid.todayTxCount, 1);
      expect(dashboardBeforeVoid.todayItemsSold, 2);

      // 4. VOID TRANSAKSI
      await saleRepo.voidSale(
        saleId: checkoutResult.sale.id,
        reason: 'Customer membatalkan pembelian',
      );

      // Verifikasi status transaksi menjadi void
      final voidedSale = await saleRepo.getSaleById(checkoutResult.sale.id);
      expect(voidedSale?.status, 'void');
      expect(voidedSale?.voidReason, 'Customer membatalkan pembelian');

      // 5. CEK STOK & AUDIT
      // Stok kembali utuh menjadi 20
      var productAfterVoid = await productRepo.getProductById(productId);
      expect(productAfterVoid?.currentStock, 20);

      // Running balance pada mutasi stok mencatat riwayat lengkap: adjustment (+20) -> sale (-2) -> void (+2)
      final movements = await stockRepo.getMovementsByProduct(productId);
      expect(movements.length, 3);
      expect(movements.any((m) => m.type == 'adjustment' && m.qtyChange == 20), isTrue);
      expect(movements.any((m) => m.type == 'sale' && m.qtyChange == -2), isTrue);
      expect(movements.any((m) => m.type == 'void' && m.qtyChange == 2), isTrue);

      // 6. LAPORAN & DASHBOARD PASCA VOID
      // Omzet mengabaikan transaksi void (omzet kembali 0)
      var dashboardAfterVoid = await reportRepo.getDashboardData();
      expect(dashboardAfterVoid.todayOmzet, 0);
      expect(dashboardAfterVoid.todayTxCount, 0);
      expect(dashboardAfterVoid.todayItemsSold, 0);
    });
  });

  group('Prompt 17: Performance & Large Dataset Benchmark', () {
    test('Generate data contoh skala besar, ukur query muat < 1 detik, lalu bersihkan', () async {
      devController = DeveloperPanelController();

      // Buat data contoh (200 produk & 500 transaksi pada in-memory DB untuk uji kecepatan & performa)
      final genWatch = Stopwatch()..start();
      await devController.generateSampleData(targetProducts: 200, targetSales: 500);
      genWatch.stop();
      // ignore: avoid_print
      print('Waktu generate 200 produk & 500 sales sampel: ${genWatch.elapsedMilliseconds} ms');

      // 1. Ukur Waktu Muat Dashboard
      final dashWatch = Stopwatch()..start();
      final dashboard = await reportRepo.getDashboardData();
      dashWatch.stop();
      // ignore: avoid_print
      print('Waktu muat Dashboard (getDashboardData): ${dashWatch.elapsedMilliseconds} ms');
      expect(dashWatch.elapsedMilliseconds, lessThan(1000), reason: 'Dashboard harus < 1 detik');
      expect(dashboard.todayTxCount, greaterThan(0));

      // 2. Ukur Waktu Muat Daftar Produk
      final prodWatch = Stopwatch()..start();
      final allProducts = await productRepo.getAllProducts();
      prodWatch.stop();
      // ignore: avoid_print
      print('Waktu muat Produk (getAllProducts): ${prodWatch.elapsedMilliseconds} ms (${allProducts.length} produk)');
      expect(prodWatch.elapsedMilliseconds, lessThan(1000), reason: 'Daftar produk harus < 1 detik');
      expect(allProducts.length, greaterThanOrEqualTo(200));

      // 3. Ukur Waktu Muat Riwayat Penjualan (Halaman 1)
      final histWatch = Stopwatch()..start();
      final salesHistory = await saleRepo.getSalesPage(limit: 50);
      histWatch.stop();
      // ignore: avoid_print
      print('Waktu muat Riwayat Penjualan (getSalesPage 50 item): ${histWatch.elapsedMilliseconds} ms');
      expect(histWatch.elapsedMilliseconds, lessThan(1000), reason: 'Riwayat penjualan harus < 1 detik');
      expect(salesHistory.length, 50);

      // 4. Ukur Waktu Muat Laporan Lengkap (Aktifkan Semi-Premium untuk membuka fitur)
      await devController.setInstantTier(Tier.semi);
      final reportWatch = Stopwatch()..start();
      final now = DateTime.now();
      final fullReport = await reportRepo.getFullReport(
        from: now.subtract(const Duration(days: 30)),
        to: now,
      );
      reportWatch.stop();
      // ignore: avoid_print
      print('Waktu muat Laporan Lengkap 30 hari: ${reportWatch.elapsedMilliseconds} ms');
      expect(reportWatch.elapsedMilliseconds, lessThan(1000), reason: 'Laporan harus < 1 detik');
      expect(fullReport.summary.txCount, greaterThan(0));

      // 5. Bersihkan data contoh
      final delWatch = Stopwatch()..start();
      await devController.deleteSampleData();
      delWatch.stop();
      // ignore: avoid_print
      print('Waktu hapus data sampel: ${delWatch.elapsedMilliseconds} ms');
      expect(devController.sampleProductCount.value, 0);
      expect(devController.sampleSaleCount.value, 0);
    });
  });
}
