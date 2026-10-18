import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_keys.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
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

  late User testUser;
  late Product testProductA;
  late Product testProductB;

  setUp(() async {
    await initializeDateFormatting('id_ID', null);
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'prompt-10-test-device-uuid',
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
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao, stockRepo);
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

    await storeRepo.insertStore(
      const StoresCompanion(
        id: Value(1),
        name: Value('Toko Prompt 10 POS'),
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
        displayName: const Value('Owner POS'),
        isActive: const Value(true),
      ),
    );

    await authService.init();
    await permissionService.init();
    testUser = authService.currentUser.value!;

    // Products
    final idA = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Kopi Susu Gula Aren'),
        sellPrice: Value(18000),
        costPrice: Value(10000),
        currentStock: Value(30),
        isActive: Value(true),
      ),
    );
    testProductA = (await productRepo.getProductById(idA))!;

    final idB = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Roti Bakar Cokelat'),
        sellPrice: Value(15000),
        costPrice: Value(8000),
        currentStock: Value(20),
        isActive: Value(true),
      ),
    );
    testProductB = (await productRepo.getProductById(idB))!;
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 10 Requirements Tests - Riwayat & Void', () {
    test('1. Void mengembalikan stok produk tepat dan mencatat stock_movement type void', () async {
      // 1. Checkout beli 3 Kopi dan 2 Roti
      final checkout = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductA.id,
            productName: testProductA.name,
            qty: 3,
            price: testProductA.sellPrice,
            costPrice: testProductA.costPrice,
          ),
          CheckoutCartItem(
            productId: testProductB.id,
            productName: testProductB.name,
            qty: 2,
            price: testProductB.sellPrice,
            costPrice: testProductB.costPrice,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 100000),
        ],
      );

      // Verifikasi stok berkurang setelah checkout
      var pA = (await productRepo.getProductById(testProductA.id))!;
      var pB = (await productRepo.getProductById(testProductB.id))!;
      expect(pA.currentStock, 27); // 30 - 3
      expect(pB.currentStock, 18); // 20 - 2

      // 2. Batalkan transaksi (VOID)
      final voided = await saleRepo.voidSale(
        saleId: checkout.sale.id,
        reason: 'Pelanggan salah pesan dan minta batal',
      );

      expect(voided.status, 'void');
      expect(voided.voidReason, 'Pelanggan salah pesan dan minta batal');
      expect(voided.voidedBy, testUser.id);
      expect(voided.voidedAt, isNotNull);

      // 3. Verifikasi stok kembali utuh
      pA = (await productRepo.getProductById(testProductA.id))!;
      pB = (await productRepo.getProductById(testProductB.id))!;
      expect(pA.currentStock, 30);
      expect(pB.currentStock, 20);

      // 4. Verifikasi mutasi stok type 'void' tercatat dengan qtyChange positif
      final movementsA = await stockRepo.getMovementsByProduct(testProductA.id);
      final voidMovementA = movementsA.firstWhereOrNull((m) => m.type == 'void');
      expect(voidMovementA, isNotNull);
      expect(voidMovementA!.qtyChange, 3);
      expect(voidMovementA.refId, checkout.sale.id);
      expect(voidMovementA.note, contains('Pelanggan salah pesan'));

      final movementsB = await stockRepo.getMovementsByProduct(testProductB.id);
      final voidMovementB = movementsB.firstWhereOrNull((m) => m.type == 'void');
      expect(voidMovementB, isNotNull);
      expect(voidMovementB!.qtyChange, 2);
    });

    test('2. Void dua kali pada transaksi yang sama ditolak (ALREADY_VOIDED)', () async {
      final checkout = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductA.id,
            productName: testProductA.name,
            qty: 5,
            price: testProductA.sellPrice,
            costPrice: testProductA.costPrice,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 90000),
        ],
      );

      // Void pertama sukses
      await saleRepo.voidSale(
        saleId: checkout.sale.id,
        reason: 'Void pertama valid',
      );

      var pA = (await productRepo.getProductById(testProductA.id))!;
      expect(pA.currentStock, 30);

      // Void kedua harus ditolak
      expect(
        () => saleRepo.voidSale(
          saleId: checkout.sale.id,
          reason: 'Void kedua seharusnya ditolak',
        ),
        throwsA(predicate((e) => e is AppException && e.code == 'ALREADY_VOIDED')),
      );

      // Stok tidak boleh bertambah lagi (tetap 30)
      pA = (await productRepo.getProductById(testProductA.id))!;
      expect(pA.currentStock, 30);
    });

    test('3. Snapshot item tidak berubah setelah transaksi di-void dan harga produk diedit', () async {
      final checkout = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductA.id,
            productName: testProductA.name,
            qty: 2,
            price: 18000,
            costPrice: 10000,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 50000),
        ],
      );

      // Ambil snapshot item sebelum void
      final itemsBefore = await saleRepo.getItemsBySaleId(checkout.sale.id);
      expect(itemsBefore.first.productName, 'Kopi Susu Gula Aren');
      expect(itemsBefore.first.price, 18000);
      expect(itemsBefore.first.costPrice, 10000);
      expect(itemsBefore.first.qty, 2);

      // Void transaksi
      await saleRepo.voidSale(
        saleId: checkout.sale.id,
        reason: 'Ubah harga simulasi',
      );

      // Ubah harga dan nama produk di master data products
      await productRepo.updateProduct(
        ProductsCompanion(
          id: Value(testProductA.id),
          name: const Value('Kopi Susu Gula Aren Baru'),
          sellPrice: const Value(25000),
          costPrice: const Value(15000),
        ),
      );

      // Pastikan snapshot item tetap sama persis seperti saat checkout
      final itemsAfter = await saleRepo.getItemsBySaleId(checkout.sale.id);
      expect(itemsAfter.first.productName, 'Kopi Susu Gula Aren');
      expect(itemsAfter.first.price, 18000);
      expect(itemsAfter.first.costPrice, 10000);
      expect(itemsAfter.first.qty, 2);
    });

    test('4. Omzet ringkasan (harian dan agregat) mengabaikan transaksi void', () async {
      final now = DateTime.now();

      // Transaksi 1: Completed, total 36.000 (2 x 18.000)
      final sale1 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductA.id,
            productName: testProductA.name,
            qty: 2,
            price: testProductA.sellPrice,
            costPrice: testProductA.costPrice,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 36000),
        ],
        transactionTime: now,
      );
      expect(sale1.sale.status, 'completed');

      // Transaksi 2: Total 15.000 (1 x 15.000), lalu di-VOID
      final sale2 = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductB.id,
            productName: testProductB.name,
            qty: 1,
            price: testProductB.sellPrice,
            costPrice: testProductB.costPrice,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 15000),
        ],
        transactionTime: now,
      );

      // Void transaksi 2
      await saleRepo.voidSale(
        saleId: sale2.sale.id,
        reason: 'Pesanan dibatalkan',
      );

      // Ringkasan Harian
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 1));
      final dailySummaries = await saleRepo.getDailySummaries(from: from, to: to);

      expect(dailySummaries.isNotEmpty, isTrue);
      // Omzet harian HANYA menghitung transaksi completed (36.000), mengabaikan 15.000 void
      expect(dailySummaries.first.totalRevenue, 36000);
      expect(dailySummaries.first.transactionCount, 1);

      // Ringkasan Agregat
      final aggregate = await saleRepo.getAggregateSummary(
        startDate: from,
        endDate: to,
      );
      expect(aggregate.totalRevenue, 36000);
      expect(aggregate.transactionCount, 2); // 2 transaksi total (1 completed + 1 void)
    });

    test('5. Kasir tanpa izin pos.void ditolak melakukan void di repository', () async {
      // 1. Buat transaksi completed
      final checkout = await saleRepo.checkout(
        cashierId: testUser.id,
        deviceId: 'TEST-DEV',
        items: [
          CheckoutCartItem(
            productId: testProductA.id,
            productName: testProductA.name,
            qty: 1,
            price: testProductA.sellPrice,
            costPrice: testProductA.costPrice,
          ),
        ],
        payments: const [
          CheckoutPayment(method: 'cash', amount: 20000),
        ],
      );

      // 2. Ubah mode toko ke 'team' dengan login wajib
      await storeRepo.updateStore(
        const StoresCompanion(
          id: Value(1),
          name: Value('Toko Tim'),
          mode: Value('team'),
          requireLogin: Value(true),
        ),
      );
      await authService.refreshState();

      // 3. Buat akun kasir biasa (peran Kasir tidak memiliki pos.void secara default)
      final kasirRole = await roleRepo.getRoleByName('Kasir');
      final kasirId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('kasir_biasa'),
          displayName: const Value('Kasir Biasa'),
          roleId: Value(kasirRole!.id),
          isActive: const Value(true),
        ),
      );
      final kasirUser = (await userRepo.getUserById(kasirId))!;

      // Login sebagai kasir biasa
      authService.currentUser.value = kasirUser;
      await permissionService.refreshPermissions();

      expect(permissionService.can(PermissionKeys.posVoid), isFalse);

      // 4. Mencoba void transaksi ditolak oleh repository
      expect(
        () => saleRepo.voidSale(
          saleId: checkout.sale.id,
          reason: 'Kasir mencoba void tanpa izin',
        ),
        throwsA(
          predicate((e) => e is AppException && e.code == 'FORBIDDEN_VOID'),
        ),
      );
    });
  });
}
