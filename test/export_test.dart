import 'dart:convert';
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
import 'package:pos_me/app/data/local/daos/category_dao.dart';
import 'package:pos_me/app/data/local/daos/opname_dao.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/purchase_dao.dart';
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/sale_dao.dart';
import 'package:pos_me/app/data/local/daos/stock_dao.dart';
import 'package:pos_me/app/data/local/daos/store_dao.dart';
import 'package:pos_me/app/data/local/daos/supplier_dao.dart';
import 'package:pos_me/app/data/local/daos/unit_dao.dart';
import 'package:pos_me/app/data/local/daos/user_dao.dart';
import 'package:pos_me/app/data/models/export_models.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/export_repository.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';

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
  late ProductDao productDao;
  late CategoryDao categoryDao;
  late UnitDao unitDao;
  late SupplierDao supplierDao;
  late SaleDao saleDao;
  late StockDao stockDao;
  late OpnameDao opnameDao;
  late PurchaseDao purchaseDao;
  late AuditDao auditDao;
  late ReportDao reportDao;
  late RoleDao roleDao;
  late StoreDao storeDao;
  late UserDao userDao;

  late ExportRepository exportRepo;
  late AuditRepository auditRepo;
  late RoleRepository roleRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;

  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuthService authService;

  late User ownerUser;
  late User cashierUser;

  setUp(() async {
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    productDao = db.productDao;
    categoryDao = db.categoryDao;
    unitDao = db.unitDao;
    supplierDao = db.supplierDao;
    saleDao = db.saleDao;
    stockDao = db.stockDao;
    opnameDao = db.opnameDao;
    purchaseDao = db.purchaseDao;
    auditDao = db.auditDao;
    reportDao = ReportDao(db);
    roleDao = db.roleDao;
    storeDao = db.storeDao;
    userDao = db.userDao;

    storeRepo = StoreRepository(storeDao);
    userRepo = UserRepository(userDao);
    roleRepo = RoleRepository(roleDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);

    // Seed roles
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final roles = await roleRepo.getAllRoles();
    final ownerRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'owner').id;
    final cashierRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'kasir').id;

    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko POS Me'),
        mode: drift.Value('solo'),
        requireLogin: drift.Value(false),
      ),
    );

    // Setup entitlement & feature gate
    entitlementProvider = MockEntitlementProvider(Tier.semi);
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    featureGate.tier.value = Tier.semi;
    Get.put<FeatureGate>(featureGate, permanent: true);

    // Setup audit
    auditRepo = AuditRepository(auditDao);
    Get.put<AuditDao>(auditDao, permanent: true);
    Get.put<AuditRepository>(auditRepo, permanent: true);
    Get.put<AuditService>(AuditService(auditRepo), permanent: true);

    // Setup auth & permission
    authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService, permanent: true);

    // Setup ExportRepository
    exportRepo = ExportRepository(
      db: db,
      productDao: productDao,
      saleDao: saleDao,
      stockDao: stockDao,
      opnameDao: opnameDao,
      purchaseDao: purchaseDao,
      auditDao: auditDao,
      reportDao: reportDao,
    );
    Get.put<ExportRepository>(exportRepo, permanent: true);

    // Buat Owner user
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('owner'),
        displayName: const drift.Value('Pemilik Toko'),
        roleId: drift.Value(ownerRoleId),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    // Buat Kasir user
    final cashierId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('kasir1'),
        displayName: const drift.Value('Kasir Utama'),
        roleId: drift.Value(cashierRoleId),
      ),
    );
    cashierUser = (await userRepo.getUserById(cashierId))!;

    // Login sebagai Owner secara default
    authService.currentUser.value = ownerUser;
    await authService.refreshState();
    await permissionService.refreshPermissions();

    // Seed master data contoh
    final catId = await categoryDao.insertCategory(
      const CategoriesCompanion(name: drift.Value('Minuman')),
    );
    final unitId = await unitDao.insertUnit(
      const UnitsCompanion(
        name: drift.Value('cup'),
        symbol: drift.Value('cup'),
      ),
    );
    final suppId = await supplierDao.insertSupplier(
      const SuppliersCompanion(
        name: drift.Value('PT Supplier Kopi'),
        phone: drift.Value('08123456789'),
      ),
    );

    // Produk
    final prodId = await productDao.insertProduct(
      ProductsCompanion(
        internalCode: const drift.Value('P000001'),
        name: const drift.Value('Kopi Susu Senja'),
        barcode: const drift.Value('899000111222'),
        sku: const drift.Value('KOP-001'),
        categoryId: drift.Value(catId),
        unitId: drift.Value(unitId),
        costPrice: const drift.Value(7000),
        sellPrice: const drift.Value(15000),
        currentStock: const drift.Value(50),
        minStock: const drift.Value(10),
        isActive: const drift.Value(true),
      ),
    );

    // Transaksi penjualan
    final saleId = await saleDao.insertSale(
      SalesCompanion(
        uuid: const drift.Value('uuid-sale-1'),
        invoiceNo: const drift.Value('INV-20261019-001'),
        deviceId: const drift.Value('dev-1'),
        cashierId: drift.Value(ownerUser.id),
        subtotal: const drift.Value(30000),
        discount: const drift.Value(0),
        tax: const drift.Value(0),
        total: const drift.Value(30000),
        status: const drift.Value('completed'),
        createdAt: drift.Value(DateTime.now()),
      ),
    );
    await saleDao.insertSaleItem(
      SaleItemsCompanion(
        saleId: drift.Value(saleId),
        productId: drift.Value(prodId),
        productName: const drift.Value('Kopi Susu Senja'),
        qty: const drift.Value(2),
        price: const drift.Value(15000),
        costPrice: const drift.Value(7000),
        subtotal: const drift.Value(30000),
      ),
    );
    await saleDao.insertPayment(
      PaymentsCompanion(
        saleId: drift.Value(saleId),
        method: const drift.Value('Tunai'),
        amount: const drift.Value(30000),
      ),
    );

    // Mutasi stok
    await stockDao.insertMovement(
      StockMovementsCompanion(
        uuid: const drift.Value('uuid-sm-1'),
        productId: drift.Value(prodId),
        type: const drift.Value('sale'),
        qtyChange: const drift.Value(-2),
        refTable: const drift.Value('sales'),
        refId: drift.Value(saleId),
        createdBy: drift.Value(ownerUser.id),
      ),
    );

    // Pembelian
    final purchaseId = await purchaseDao.insertPurchase(
      PurchasesCompanion(
        uuid: const drift.Value('uuid-pur-1'),
        deviceId: const drift.Value('dev-1'),
        refNo: const drift.Value('PO-20261019-01'),
        supplierId: drift.Value(suppId),
        date: drift.Value(DateTime.now()),
        total: const drift.Value(70000),
        status: const drift.Value('received'),
      ),
    );
    await purchaseDao.insertPurchaseItem(
      PurchaseItemsCompanion(
        purchaseId: drift.Value(purchaseId),
        productId: drift.Value(prodId),
        qty: const drift.Value(10),
        costPrice: const drift.Value(7000),
      ),
    );

    // Opname
    final opnameId = await opnameDao.insertOpname(
      StockOpnamesCompanion(
        uuid: const drift.Value('uuid-opn-1'),
        deviceId: const drift.Value('dev-1'),
        code: const drift.Value('OPN-20261019-01'),
        date: drift.Value(DateTime.now()),
        status: const drift.Value('final'),
        note: const drift.Value('Hitung akhir shift'),
        createdBy: drift.Value(ownerUser.id),
      ),
    );
    await opnameDao.insertOpnameItem(
      StockOpnameItemsCompanion(
        opnameId: drift.Value(opnameId),
        productId: drift.Value(prodId),
        systemQty: const drift.Value(50),
        countedQty: const drift.Value(48),
        difference: const drift.Value(-2),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('1. Dual-Layer Gating & Access Control Tests', () {
    test('Tier Gratis DITOLAK saat memanggil ekspor (FEATURE_LOCKED)', () async {
      featureGate.tier.value = Tier.free;

      expect(
        () => exportRepo.exportProducts(format: ExportFormat.csv),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );

      expect(
        () => exportRepo.exportSales(format: ExportFormat.csv),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );

      expect(
        () => exportRepo.exportStockMovements(format: ExportFormat.xlsx),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );
    });

    test('User tanpa izin report.export DITOLAK (FORBIDDEN)', () async {
      await storeDao.updateStore(
        const StoresCompanion(
          id: drift.Value(1),
          name: drift.Value('Toko POS Me'),
          mode: drift.Value('multi_user'),
          requireLogin: drift.Value(true),
        ),
      );
      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(
        () => exportRepo.exportProducts(format: ExportFormat.csv),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );

      expect(
        () => exportRepo.exportSales(format: ExportFormat.csv),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('Ekspor log aktivitas tanpa izin audit.view DITOLAK (FORBIDDEN)', () async {
      await storeDao.updateStore(
        const StoresCompanion(
          id: drift.Value(1),
          name: drift.Value('Toko POS Me'),
          mode: drift.Value('multi_user'),
          requireLogin: drift.Value(true),
        ),
      );
      // Kasir tidak memiliki audit.view
      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(
        () => exportRepo.exportAuditLogs(format: ExportFormat.csv),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('2. CSV Format & UTF-8 BOM Verification', () {
    test('Semua berkas CSV memiliki header UTF-8 BOM [0xEF, 0xBB, 0xBF]', () async {
      final resProducts = await exportRepo.exportProducts(format: ExportFormat.csv);
      expect(resProducts.bytes.length, greaterThanOrEqualTo(3));
      expect(resProducts.bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

      final resSales = await exportRepo.exportSales(format: ExportFormat.csv);
      expect(resSales.bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

      final resStock = await exportRepo.exportStockMovements(format: ExportFormat.csv);
      expect(resStock.bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

      final resPurchases = await exportRepo.exportPurchases(format: ExportFormat.csv);
      expect(resPurchases.bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

      final resOpname = await exportRepo.exportStockOpname(format: ExportFormat.csv);
      expect(resOpname.bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));
    });

    test('Konten teks CSV terbaca rapi setelah memotong BOM 3 byte', () async {
      final res = await exportRepo.exportProducts(format: ExportFormat.csv);
      final rawString = utf8.decode(res.bytes.sublist(3));

      expect(rawString, contains('Kode Internal'));
      expect(rawString, contains('Nama Produk'));
      expect(rawString, contains('Kopi Susu Senja'));
      expect(rawString, contains('899000111222'));
    });
  });

  group('3. Sensitive Column & Profit Censorship Tests', () {
    test('Owner dengan product.view_cost menyertakan kolom Harga Beli pada katalog produk', () async {
      final res = await exportRepo.exportProducts(format: ExportFormat.csv);
      final text = utf8.decode(res.bytes.sublist(3));

      expect(text, contains('Harga Beli'));
      expect(text, contains('7000'));
    });

    test('Owner dengan report.view_profit menyertakan modal snapshot dan laba kotor pada penjualan', () async {
      final res = await exportRepo.exportSales(format: ExportFormat.csv);
      final text = utf8.decode(res.bytes.sublist(3));

      expect(text, contains('Harga Modal Snapshot'));
      expect(text, contains('Laba Kotor Item'));
      expect(text, contains('7000')); // modal per item
      expect(text, contains('16000')); // laba kotor item = 30000 - (2 * 7000) = 16000
    });

    test('Ekspor Laporan Lengkap menyensor HPP & Laba saat isProfitVisible = false', () async {
      final reportRepo = ReportRepository(reportDao);
      final reportData = await reportRepo.getFullReport(
        from: DateTime.now().subtract(const Duration(days: 7)),
        to: DateTime.now().add(const Duration(days: 1)),
      );

      expect(reportData, isNotNull);

      // Ekspor saat profit visible
      final resProfit = await exportRepo.exportFullReport(reportData, format: ExportFormat.csv);
      final textProfit = utf8.decode(resProfit.bytes.sublist(3));
      expect(textProfit, contains('HPP (Harga Pokok Penjualan)'));
      expect(textProfit, contains('Laba Kotor'));

      // Ekspor dengan data laba disensor
      final censoredReportData = FullReportData(
        from: reportData.from,
        to: reportData.to,
        summary: reportData.summary.copyWithProfitHidden(),
        avgTxValue: reportData.avgTxValue,
        topProducts: reportData.topProducts.map((p) => p.copyWithProfitHidden()).toList(),
        categorySales: reportData.categorySales,
        paymentMethodSales: reportData.paymentMethodSales,
        cashierSales: reportData.cashierSales,
        hourlySales: reportData.hourlySales,
        stockValuation: null,
        stockAlerts: reportData.stockAlerts,
        voidSummary: reportData.voidSummary,
        isProfitVisible: false,
      );

      final resCensored = await exportRepo.exportFullReport(censoredReportData, format: ExportFormat.csv);
      final textCensored = utf8.decode(resCensored.bytes.sublist(3));
      expect(textCensored, isNot(contains('HPP (Harga Pokok Penjualan)')));
      expect(textCensored, isNot(contains('Laba Kotor')));
    });
  });

  group('4. Excel Spreadsheet (XLSX) Generation Tests', () {
    test('XLSX ter-generate valid dan byte tidak kosong untuk semua entitas', () async {
      final xProd = await exportRepo.exportProducts(format: ExportFormat.xlsx);
      expect(xProd.bytes.isNotEmpty, isTrue);
      expect(xProd.fileName.endsWith('.xlsx'), isTrue);

      final xSales = await exportRepo.exportSales(format: ExportFormat.xlsx);
      expect(xSales.bytes.isNotEmpty, isTrue);

      final xStock = await exportRepo.exportStockMovements(format: ExportFormat.xlsx);
      expect(xStock.bytes.isNotEmpty, isTrue);

      final xPurchases = await exportRepo.exportPurchases(format: ExportFormat.xlsx);
      expect(xPurchases.bytes.isNotEmpty, isTrue);

      final xOpname = await exportRepo.exportStockOpname(format: ExportFormat.xlsx);
      expect(xOpname.bytes.isNotEmpty, isTrue);

      final reportRepo = ReportRepository(reportDao);
      final reportData = await reportRepo.getFullReport(
        from: DateTime.now().subtract(const Duration(days: 7)),
        to: DateTime.now().add(const Duration(days: 1)),
      );
      final xFull = await exportRepo.exportFullReport(reportData, format: ExportFormat.xlsx);
      expect(xFull.bytes.isNotEmpty, isTrue);
    });
  });

  group('5. Audit Trail Recording Tests', () {
    test('Setiap ekspor berhasil mencatat log ke AuditService dengan action export.run', () async {
      final initialLogs = await auditDao.getAllLogs();
      final initialCount = initialLogs.length;

      await exportRepo.exportProducts(format: ExportFormat.csv);

      final logsAfter = await auditDao.getAllLogs();
      expect(logsAfter.length, equals(initialCount + 1));

      final latestLog = logsAfter.first;
      expect(latestLog.action, equals(AuditActions.exportRun));
      expect(latestLog.entity, equals('product'));
      expect(latestLog.detail, contains('"format":"csv"'));
      expect(latestLog.detail, contains('"rowCount":1'));
    });
  });
}
