import 'dart:convert';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/services/pdf/receipt_pdf_service.dart';
import 'package:pos_me/app/core/services/scanner/scanner_service.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
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

  late Store testStore;
  late User testUser;
  late Product prodA;
  late Product prodB;

  setUp(() async {
    await initializeDateFormatting('id_ID', null);
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'pos-test-device-uuid',
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

    Get.put<ProductRepository>(productRepo);
    Get.put<StockRepository>(stockRepo);
    Get.put<SaleRepository>(saleRepo);
    Get.put<SettingsRepository>(settingsRepo);
    Get.put<CategoryRepository>(categoryRepo);

    // Setup Toko & Kasir
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Uji Kasir'),
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
        username: const Value('owner_pos'),
        displayName: const Value('Owner Kasir'),
        isActive: const Value(true),
      ),
    );

    await authService.init();
    await permissionService.init();

    testStore = authService.currentStore.value!;
    testUser = authService.currentUser.value!;

    // Seed 2 Produk Uji
    final catId = await categoryRepo.insertCategory(
      const CategoriesCompanion(name: Value('Makanan')),
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
        sellPrice: const Value(15000),
        currentStock: const Value(10),
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
        name: 'Roti Bakar Cokelat',
        costPrice: const Value(6000),
        sellPrice: const Value(12000),
        currentStock: const Value(5),
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
  });

  group('SaleRepository Atomic Checkout Tests', () {
    test('Successful checkout accurately decrements stock and creates movements atomically', () async {
      final items = [
        CheckoutCartItem(
          productId: prodA.id,
          productName: prodA.name,
          qty: 2,
          price: prodA.sellPrice,
          costPrice: prodA.costPrice,
          discount: 0,
        ),
        CheckoutCartItem(
          productId: prodB.id,
          productName: prodB.name,
          qty: 1,
          price: prodB.sellPrice,
          costPrice: prodB.costPrice,
          discount: 2000,
        ),
      ];

      // Item 1: 2 * 15.000 = 30.000
      // Item 2: 1 * (12.000 - 2.000) = 10.000
      // Subtotal = 42.000, Disc overall = 2.000 -> Total = 38.000
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 50000),
      ];

      final result = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'pos-test-device-uuid',
        items: items,
        payments: payments,
        overallDiscount: 2000,
        allowNegativeStock: false,
      );

      expect(result.sale.subtotal, equals(42000));
      expect(result.sale.discount, equals(4000));
      expect(result.sale.total, equals(38000));
      expect(result.sale.paid, equals(50000));
      expect(result.sale.change, equals(12000));
      expect(result.items.length, equals(2));
      expect(result.payments.length, equals(1));

      // Verifikasi stok berkurang di database
      final updatedProdA = await productRepo.getProductById(prodA.id);
      final updatedProdB = await productRepo.getProductById(prodB.id);
      expect(updatedProdA!.currentStock, equals(8)); // 10 - 2
      expect(updatedProdB!.currentStock, equals(4)); // 5 - 1

      // Verifikasi tabel stock_movements
      final movementsA = await db.stockDao.getMovementsByProduct(prodA.id);
      expect(movementsA.length, equals(1));
      expect(movementsA.first.qtyChange, equals(-2));
      expect(movementsA.first.type, equals('sale'));
      expect(movementsA.first.refTable, equals('sales'));
      expect(movementsA.first.refId, equals(result.sale.id));

      final movementsB = await db.stockDao.getMovementsByProduct(prodB.id);
      expect(movementsB.length, equals(1));
      expect(movementsB.first.qtyChange, equals(-1));
    });

    test('Insufficient stock with allowNegativeStock = false rolls back entire transaction', () async {
      // prodA currentStock is 10, request 15
      final items = [
        CheckoutCartItem(
          productId: prodA.id,
          productName: prodA.name,
          qty: 15,
          price: prodA.sellPrice,
          costPrice: prodA.costPrice,
        ),
      ];
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 250000),
      ];

      expect(
        () async => await saleRepo.checkout(
          cashierId: testUser.id,
          deviceId: 'pos-test-device-uuid',
          items: items,
          payments: payments,
          allowNegativeStock: false,
        ),
        throwsA(isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('tidak mencukupi'),
        )),
      );

      // Verifikasi rollback penuh: stok prodA tidak berubah
      final checkProdA = await productRepo.getProductById(prodA.id);
      expect(checkProdA!.currentStock, equals(10));

      // Tidak ada baris sales atau stock_movements yang tersimpan
      final allSales = await db.saleDao.getAllSales();
      expect(allSales.isEmpty, isTrue);

      final movementsA = await db.stockDao.getMovementsByProduct(prodA.id);
      expect(movementsA.isEmpty, isTrue);
    });

    test('Checkout with allowNegativeStock = true succeeds and decrements stock below zero', () async {
      final items = [
        CheckoutCartItem(
          productId: prodB.id, // Current stock is 5
          productName: prodB.name,
          qty: 8, // Exceeds by 3
          price: prodB.sellPrice,
          costPrice: prodB.costPrice,
        ),
      ];
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 96000),
      ];

      final result = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'pos-test-device-uuid',
        items: items,
        payments: payments,
        allowNegativeStock: true,
      );

      expect(result.sale.total, equals(96000));

      final checkProdB = await productRepo.getProductById(prodB.id);
      expect(checkProdB!.currentStock, equals(-3)); // 5 - 8 = -3

      final movementsB = await db.stockDao.getMovementsByProduct(prodB.id);
      expect(movementsB.length, equals(1));
      expect(movementsB.first.qtyChange, equals(-8));
    });

    test('Sequential invoice numbers are generated uniquely across checkouts', () async {
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 20000),
      ];

      final res1 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'dev1-uuid',
        items: [
          CheckoutCartItem(
            productId: prodA.id,
            productName: prodA.name,
            qty: 1,
            price: prodA.sellPrice,
            costPrice: prodA.costPrice,
          ),
        ],
        payments: payments,
      );

      final res2 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'dev1-uuid',
        items: [
          CheckoutCartItem(
            productId: prodA.id,
            productName: prodA.name,
            qty: 1,
            price: prodA.sellPrice,
            costPrice: prodA.costPrice,
          ),
        ],
        payments: payments,
      );

      final res3 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'dev1-uuid',
        items: [
          CheckoutCartItem(
            productId: prodA.id,
            productName: prodA.name,
            qty: 1,
            price: prodA.sellPrice,
            costPrice: prodA.costPrice,
          ),
        ],
        payments: payments,
      );

      expect(res1.sale.invoiceNo, endsWith('-0001'));
      expect(res2.sale.invoiceNo, endsWith('-0002'));
      expect(res3.sale.invoiceNo, endsWith('-0003'));

      // Semua invoice unik
      final numbers = {res1.sale.invoiceNo, res2.sale.invoiceNo, res3.sale.invoiceNo};
      expect(numbers.length, equals(3));
    });

    test('Split payments accounting and change calculation', () async {
      // Total 27.000: prodA (15.000) + prodB (12.000)
      final items = [
        CheckoutCartItem(
          productId: prodA.id,
          productName: prodA.name,
          qty: 1,
          price: prodA.sellPrice,
          costPrice: prodA.costPrice,
        ),
        CheckoutCartItem(
          productId: prodB.id,
          productName: prodB.name,
          qty: 1,
          price: prodB.sellPrice,
          costPrice: prodB.costPrice,
        ),
      ];

      // Split pay: Cash 20.000 + QRIS 10.000 = Total Paid 30.000 -> Change 3.000
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 20000),
        const CheckoutPayment(method: 'qris', amount: 10000),
      ];

      final result = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'split-dev',
        items: items,
        payments: payments,
      );

      expect(result.sale.total, equals(27000));
      expect(result.sale.paid, equals(30000));
      expect(result.sale.change, equals(3000));
      expect(result.payments.length, equals(2));
      expect(result.payments[0].method, equals('cash'));
      expect(result.payments[0].amount, equals(20000));
      expect(result.payments[1].method, equals('qris'));
      expect(result.payments[1].amount, equals(10000));
    });

    test('Underpaid checkout is rejected with AppException', () async {
      final items = [
        CheckoutCartItem(
          productId: prodA.id,
          productName: prodA.name,
          qty: 1,
          price: prodA.sellPrice,
          costPrice: prodA.costPrice,
        ),
      ];
      // Total 15.000, bayar 10.000
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 10000),
      ];

      expect(
        () async => await saleRepo.checkout(
          cashierId: testUser.id,
          deviceId: 'underpaid-dev',
          items: items,
          payments: payments,
        ),
        throwsA(isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('Pembayaran kurang'),
        )),
      );
    });
  });

  group('ReceiptPdfService Tests', () {
    test('Generates valid non-empty PDF bytes for 58mm thermal receipt', () async {
      final items = [
        CheckoutCartItem(
          productId: prodA.id,
          productName: prodA.name,
          qty: 2,
          price: prodA.sellPrice,
          costPrice: prodA.costPrice,
        ),
      ];
      final payments = [
        const CheckoutPayment(method: 'cash', amount: 30000),
      ];

      final checkoutResult = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'pdf-dev',
        items: items,
        payments: payments,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        store: testStore,
        cashierName: testUser.displayName,
        sale: checkoutResult.sale,
        items: checkoutResult.items,
        payments: checkoutResult.payments,
        receiptWidth: '58',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);

      // Cek header PDF valid (%PDF-)
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header.startsWith('%PDF'), isTrue);
    });

    test('Generates valid non-empty PDF bytes for 80mm thermal receipt', () async {
      final items = [
        CheckoutCartItem(
          productId: prodB.id,
          productName: prodB.name,
          qty: 1,
          price: prodB.sellPrice,
          costPrice: prodB.costPrice,
        ),
      ];
      final payments = [
        const CheckoutPayment(method: 'qris', amount: 12000),
      ];

      final checkoutResult = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'pdf-dev',
        items: items,
        payments: payments,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        store: testStore,
        cashierName: testUser.displayName,
        sale: checkoutResult.sale,
        items: checkoutResult.items,
        payments: checkoutResult.payments,
        receiptWidth: '80',
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header.startsWith('%PDF'), isTrue);
    });
  });

  group('PosController Reactive Cart & Features Tests', () {
    late PosController controller;

    setUp(() {
      controller = PosController();
      Get.put<PosController>(controller);
      controller.onInit();
      controller.allProducts.assignAll([prodA, prodB]);
    });

    tearDown(() {
      controller.onClose();
    });

    test('Add product to cart and adjust quantities', () {
      controller.addToCart(prodA);
      expect(controller.cartItems.length, equals(1));
      expect(controller.cartItems.first.qty.value, equals(1));
      expect(controller.subtotalAmount, equals(15000));

      // Menambah lagi produk yang sama menambah qty +1
      controller.addToCart(prodA);
      expect(controller.cartItems.length, equals(1));
      expect(controller.cartItems.first.qty.value, equals(2));
      expect(controller.subtotalAmount, equals(30000));

      // Stepper decrement via updateQty
      controller.updateQty(controller.cartItems.first, 1);
      expect(controller.cartItems.first.qty.value, equals(1));

      // Tambah item B
      controller.addToCart(prodB);
      expect(controller.cartItems.length, equals(2));
      expect(controller.subtotalAmount, equals(27000)); // 15.000 + 12.000

      // Hapus item A
      controller.removeFromCart(controller.cartItems.first);
      expect(controller.cartItems.length, equals(1));
      expect(controller.cartItems.first.product.id, equals(prodB.id));
    });

    test('Hold and resume cart operations', () {
      controller.addToCart(prodA);
      controller.addToCart(prodB);
      expect(controller.cartItems.length, equals(2));

      // Tahan keranjang
      controller.holdCurrentCart(customName: 'Meja 5');
      expect(controller.cartItems.isEmpty, isTrue);
      expect(controller.heldCarts.length, equals(1));
      expect(controller.heldCarts.first.name, equals('Meja 5'));
      expect(controller.heldCarts.first.items.length, equals(2));

      // Lanjutkan kembali keranjang yang ditahan
      controller.resumeHeldCart(controller.heldCarts.first);
      expect(controller.cartItems.length, equals(2));
      expect(controller.heldCarts.isEmpty, isTrue);
    });

    test('Overall and item discount calculations', () {
      controller.addToCart(prodA); // 15.000
      controller.addToCart(prodB); // 12.000
      // Subtotal = 27.000

      // Item discount pada prodA: Rp 2.000
      controller.setItemDiscount(controller.cartItems.first, 2000);
      expect(controller.cartItems.first.subtotal, equals(13000));
      expect(controller.subtotalAmount, equals(27000));
      expect(controller.itemsDiscountTotal, equals(2000));

      // Overall discount: 10%
      controller.setOverallDiscount(10, isPercent: true);
      expect(controller.calculatedOverallDiscount, equals(2500));
      expect(controller.finalTotalAmount, equals(22500));

      // Ganti nominal diskon total: Rp 5.000
      controller.setOverallDiscount(5000, isPercent: false);
      expect(controller.calculatedOverallDiscount, equals(5000));
      expect(controller.finalTotalAmount, equals(20000));
    });

    test('Favorite products toggle persists in settings', () async {
      expect(controller.favoriteProductIds.contains(prodA.id), isFalse);

      await controller.toggleFavorite(prodA.id);
      expect(controller.favoriteProductIds.contains(prodA.id), isTrue);

      final val = await settingsRepo.getSetting('pos.favorite_product_ids');
      expect(val, isNotNull);
      final decoded = List<int>.from(jsonDecode(val!));
      expect(decoded.contains(prodA.id), isTrue);

      // Unfavorite
      await controller.toggleFavorite(prodA.id);
      expect(controller.favoriteProductIds.contains(prodA.id), isFalse);
    });

    test('Scan HID code automatically adds matching product', () {
      controller.onBarcodeScanned('8990001'); // Barcode of prodA
      expect(controller.cartItems.length, equals(1));
      expect(controller.cartItems.first.product.id, equals(prodA.id));
      expect(controller.cartItems.first.qty.value, equals(1));

      // Scan lagi -> bertambah qty
      controller.onBarcodeScanned('8990001');
      expect(controller.cartItems.first.qty.value, equals(2));
    });
  });
}
