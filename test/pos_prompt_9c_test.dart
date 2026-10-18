import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/printing/printer_manager.dart';
import 'package:pos_me/app/core/printing/receipt_data.dart';
import 'package:pos_me/app/core/printing/receipt_mode.dart';
import 'package:pos_me/app/core/printing/receipt_printer.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/services/pdf/receipt_pdf_service.dart';
import 'package:pos_me/app/core/services/scanner/scanner_service.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/sale_dao.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/category_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/sale_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/modules/pos/controllers/pos_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFailingReceiptPrinter implements ReceiptPrinter {
  int printCount = 0;

  @override
  Future<PrintResult> printReceipt(ReceiptData data) async {
    printCount++;
    return PrintResult.failure('Printer thermal kehabisan kertas atau offline.');
  }

  @override
  Future<PrintResult> printTest() async {
    return PrintResult.failure('Test printer gagal.');
  }

  @override
  Future<void> openCashDrawer() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late LicenseRepository licenseRepo;
  late AuditRepository auditRepo;
  late ProductRepository productRepo;
  late StockRepository stockRepo;
  late SaleRepository saleRepo;
  late SettingsRepository settingsRepo;
  late CategoryRepository categoryRepo;

  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuditService auditService;
  late AuthService authService;
  late ReceiptPdfService receiptPdfService;

  late User testUser;
  late Product prodA;
  late Product prodB;

  setUp(() async {
    await initializeDateFormatting('id_ID', null);
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'prompt-9c-test-device-uuid',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );
    stockRepo = StockRepository(db, db.stockDao, db.productDao);
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao);
    settingsRepo = SettingsRepository(db.settingsDao);
    categoryRepo = CategoryRepository(db.categoryDao);

    Get.put<SaleRepository>(saleRepo);
    Get.put<ProductRepository>(productRepo);
    Get.put<StockRepository>(stockRepo);
    Get.put<SettingsRepository>(settingsRepo);
    Get.put<CategoryRepository>(categoryRepo);

    await Get.putAsync(() => DeviceIdService().init());

    final entitlementProvider = SimulatedEntitlementProvider(licenseRepo);
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate);

    auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService);

    authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService);

    receiptPdfService = ReceiptPdfService();
    Get.put<ReceiptPdfService>(receiptPdfService);
    Get.put<ScannerService>(ScannerService());

    // Setup Toko & Kasir
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Prompt 9C'),
        address: Value('Jl. Merdeka No. 1'),
        phone: Value('08123456789'),
        mode: Value('solo'),
        requireLogin: Value(false),
        scannerType: Value('1d'),
      ),
    );

    final ownerRole = await roleRepo.getRoleByName('Owner');
    await userRepo.insertUser(
      UsersCompanion(
        roleId: Value(ownerRole!.id),
        username: const Value('kasir9c'),
        displayName: const Value('Kasir Utama'),
        isActive: const Value(true),
      ),
    );

    await authService.init();
    await permissionService.init();

    testUser = authService.currentUser.value!;

    // Seed 2 Produk Uji
    final catId = await categoryRepo.insertCategory(
      const CategoriesCompanion(name: Value('Minuman')),
    );
    final unitId = await db.unitDao.insertUnit(
      const UnitsCompanion(name: Value('Pcs'), symbol: Value('pcs')),
    );

    final prodAId = await productRepo.createProduct(
      ProductsCompanion.insert(
        categoryId: Value(catId),
        unitId: Value(unitId),
        name: 'Kopi Susu Gula Aren',
        costPrice: const Value(8000),
        sellPrice: const Value(18000),
        currentStock: const Value(50),
        minStock: const Value(2),
        barcode: const Value('8990001'),
        internalCode: const Value('P000001'),
        codeType: const Value('manufacturer'),
        isActive: const Value(true),
      ),
    );
    prodA = (await productRepo.getProductById(prodAId))!;

    final prodBId = await productRepo.createProduct(
      ProductsCompanion.insert(
        categoryId: Value(catId),
        unitId: Value(unitId),
        name: 'Roti Bakar Coklat',
        costPrice: const Value(5000),
        sellPrice: const Value(12000),
        currentStock: const Value(30),
        minStock: const Value(1),
        barcode: const Value('8990002'),
        internalCode: const Value('P000002'),
        codeType: const Value('manufacturer'),
        isActive: const Value(true),
      ),
    );
    prodB = (await productRepo.getProductById(prodBId))!;
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 9C Requirements Tests', () {
    test('1. Transaksi atomik berhasil tersimpan saat printer offline / error', () async {
      final printerManager = PrinterManager();
      Get.put<PrinterManager>(printerManager);

      await settingsRepo.setSetting(PrinterManager.keyType, 'bluetooth');
      await settingsRepo.setSetting(PrinterManager.keyTarget, '00:11:22:33:44:55');
      await settingsRepo.setSetting(PrinterManager.keyReceiptMode, 'always');
      await printerManager.loadSettings();

      final controller = PosController();
      Get.put<PosController>(controller);

      controller.addToCart(prodA); // 18.000
      expect(controller.cartItems.length, equals(1));

      // Checkout tunai 20.000
      final result = await controller.processCheckout(
        payments: const [CheckoutPayment(method: 'cash', amount: 20000)],
      );

      // Pastikan checkout SUKSES mengembalikan data Sale
      expect(result, isNotNull);
      expect(result!.sale.total, equals(18000));
      expect(result.sale.paid, equals(20000));
      expect(result.sale.change, equals(2000));
      expect(result.sale.status, equals('completed'));

      // Keranjang belanja harus sudah kosong
      expect(controller.cartItems.isEmpty, isTrue);

      // Transaksi benar-benar tersimpan di database
      final savedSale = await saleRepo.getSaleById(result.sale.id);
      expect(savedSale, isNotNull);
      expect(savedSale!.invoiceNo, equals(result.sale.invoiceNo));

      // Stok produk berkurang dari 50 menjadi 49
      final updatedProd = await productRepo.getProductById(prodA.id);
      expect(updatedProd!.currentStock, equals(49));
    });

    test('2. Mode "never" tidak mencetak struk dan langsung fokus kembali ke kasir', () async {
      final printerManager = PrinterManager();
      Get.put<PrinterManager>(printerManager);

      await settingsRepo.setSetting(PrinterManager.keyReceiptMode, 'never');
      await printerManager.loadSettings();

      final controller = PosController();
      Get.put<PosController>(controller);

      controller.addToCart(prodB); // 12.000
      expect(controller.receiptMode, equals(ReceiptMode.never));

      final result = await controller.processCheckout(
        payments: const [CheckoutPayment(method: 'cash', amount: 15000)],
      );

      expect(result, isNotNull);
      expect(result!.sale.total, equals(12000));
      expect(controller.cartItems.isEmpty, isTrue);

      // Pada mode never, tidak ada layar sukses yang diminta
      expect(controller.lastSuccessArgs, isNull);
    });

    test('3. Guard isSaving mencegah transaksi ganda saat tombol Bayar ditekan ganda cepat', () async {
      final controller = PosController();
      Get.put<PosController>(controller);

      controller.addToCart(prodA); // 18.000

      // Eksekusi dua panggilan processCheckout secara bersamaan (simulasi double tap)
      final future1 = controller.processCheckout(
        payments: const [CheckoutPayment(method: 'cash', amount: 20000)],
      );
      final future2 = controller.processCheckout(
        payments: const [CheckoutPayment(method: 'cash', amount: 20000)],
      );

      final results = await Future.wait([future1, future2]);

      // Salah satu berhasil, panggilan kedua harus bernilai null karena isSaving.value == true
      final nonNullResults = results.whereType<CheckoutResult>().toList();
      expect(nonNullResults.length, equals(1));

      // Di database hanya tercatat 1 transaksi
      final allSales = await saleRepo.getAllSales();
      expect(allSales.length, equals(1));
    });

    test('4. Riwayat: pengelompokan per hari lokal memisahkan 23:59 dan 00:01 ke hari berbeda', () async {
      final localDay1Late = DateTime(2026, 10, 18, 23, 59, 0);
      final localDay2Early = DateTime(2026, 10, 19, 0, 1, 0);

      await db.saleDao.insertSale(
        SalesCompanion(
          uuid: const Value('tx-late-1'),
          deviceId: const Value('dev-1'),
          invoiceNo: const Value('INV-261018-0001'),
          cashierId: Value(testUser.id),
          subtotal: const Value(50000),
          discount: const Value(0),
          total: const Value(50000),
          paid: const Value(50000),
          change: const Value(0),
          status: const Value('completed'),
          createdAt: Value(localDay1Late.toUtc()),
        ),
      );

      await db.saleDao.insertSale(
        SalesCompanion(
          uuid: const Value('tx-early-2'),
          deviceId: const Value('dev-1'),
          invoiceNo: const Value('INV-261019-0001'),
          cashierId: Value(testUser.id),
          subtotal: const Value(75000),
          discount: const Value(0),
          total: const Value(75000),
          paid: const Value(100000),
          change: const Value(25000),
          status: const Value('completed'),
          createdAt: Value(localDay2Early.toUtc()),
        ),
      );

      final summaries = await saleRepo.getDailySummaries(
        from: DateTime(2026, 10, 18).toUtc(),
        to: DateTime(2026, 10, 20).toUtc(),
      );

      expect(summaries.length, equals(2));

      final summaryDay2 = summaries.firstWhere((s) => s.day == '2026-10-19');
      final summaryDay1 = summaries.firstWhere((s) => s.day == '2026-10-18');

      expect(summaryDay1.transactionCount, equals(1));
      expect(summaryDay1.totalRevenue, equals(50000));

      expect(summaryDay2.transactionCount, equals(1));
      expect(summaryDay2.totalRevenue, equals(75000));
    });

    test('5. Keyset pagination dan SaleDetail memuat data transaksi secara lengkap', () async {
      final sale1 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'dev-1',
        items: [
          CheckoutCartItem(
            productId: prodA.id,
            productName: prodA.name,
            qty: 1,
            price: prodA.sellPrice,
            costPrice: prodA.costPrice,
          ),
        ],
        payments: const [CheckoutPayment(method: 'cash', amount: 20000)],
      );

      final sale2 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'dev-1',
        items: [
          CheckoutCartItem(
            productId: prodB.id,
            productName: prodB.name,
            qty: 2,
            price: prodB.sellPrice,
            costPrice: prodB.costPrice,
          ),
        ],
        payments: const [CheckoutPayment(method: 'qris', amount: 24000)],
      );

      final page1 = await saleRepo.getSalesPage(limit: 1);
      expect(page1.length, equals(1));
      expect(page1.first.sale.id, equals(sale2.sale.id));
      expect(page1.first.paymentMethods, contains('qris'));

      final cursor = SalesCursor.fromSale(page1.first.sale);
      final page2 = await saleRepo.getSalesPage(limit: 1, after: cursor);
      expect(page2.length, equals(1));
      expect(page2.first.sale.id, equals(sale1.sale.id));
      expect(page2.first.paymentMethods, contains('cash'));

      final detail = await saleRepo.getSaleDetail(sale1.sale.id);
      expect(detail, isNotNull);
      expect(detail!.cashierName, equals('Kasir Utama'));
      expect(detail.items.length, equals(1));
      expect(detail.items.first.productName, equals('Kopi Susu Gula Aren'));
      expect(detail.payments.first.method, equals('cash'));
    });
  });
}
