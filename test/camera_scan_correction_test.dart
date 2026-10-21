import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/printing/printer_manager.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/services/scanner/scanner_service.dart';
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
  late ProductRepository productRepo;
  late ScannerService scannerService;
  late PosController posController;
  late DateTime fakeTime;

  late Product productA;
  late Product productB;

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Get.put<SharedPreferences>(prefs);

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db);

    final storeRepo = StoreRepository(db.storeDao);
    final userRepo = UserRepository(db.userDao);
    final roleRepo = RoleRepository(db.roleDao);
    final licenseRepo = LicenseRepository(db.licenseDao);
    final auditRepo = AuditRepository(db.auditDao);
    final settingsRepo = SettingsRepository(db.settingsDao);
    final categoryRepo = CategoryRepository(db.categoryDao);
    productRepo = ProductRepository(db.productDao);
    final stockRepo = StockRepository(db, db.stockDao, db.productDao);
    final saleRepo = SaleRepository(
      db,
      db.saleDao,
      db.productDao,
      db.stockDao,
      stockRepo,
    );

    Get.put<StoreRepository>(storeRepo);
    Get.put<UserRepository>(userRepo);
    Get.put<RoleRepository>(roleRepo);
    Get.put<LicenseRepository>(licenseRepo);
    Get.put<AuditRepository>(auditRepo);
    Get.put<SettingsRepository>(settingsRepo);
    Get.put<CategoryRepository>(categoryRepo);
    Get.put<ProductRepository>(productRepo);
    Get.put<StockRepository>(stockRepo);
    Get.put<SaleRepository>(saleRepo);

    final deviceIdService = DeviceIdService();
    Get.put<DeviceIdService>(deviceIdService);

    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService);

    final authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService);

    final entitlementProvider = SimulatedEntitlementProvider(licenseRepo);
    final featureGate = FeatureGate(entitlementProvider);
    Get.put<FeatureGate>(featureGate);

    final permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService);

    final printerManager = PrinterManager();
    Get.put<PrinterManager>(printerManager);

    fakeTime = DateTime(2026, 1, 1, 12, 0, 0);
    scannerService = ScannerService(
      clock: () => fakeTime,
      cooldownDuration: const Duration(seconds: 1),
    );
    Get.put<ScannerService>(scannerService);

    // Seed Roles & Store
    await RoleSeeder.seedDefaultRoles(roleRepo);
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Uji Kamera'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Owner POS'),
        roleId: Value(ownerRole!.id),
      ),
    );
    authService.currentUser.value = await userRepo.getUserById(ownerId);
    await authService.refreshState();
    await permissionService.refreshPermissions();

    // Seed 2 Produk berbeda
    final catId = await categoryRepo.insertCategory(
      const CategoriesCompanion(name: Value('Makanan & Minuman')),
    );

    final prodAId = await productRepo.insertProduct(
      ProductsCompanion(
        name: const Value('Kopi Susu Gula Aren'),
        barcode: const Value('899000111'),
        sellPrice: const Value(15000),
        costPrice: const Value(8000),
        currentStock: const Value(50),
        categoryId: Value(catId),
        isActive: const Value(true),
      ),
    );
    productA = (await productRepo.getProductById(prodAId))!;

    final prodBId = await productRepo.insertProduct(
      ProductsCompanion(
        name: const Value('Roti Bakar Cokelat'),
        barcode: const Value('899000222'),
        sellPrice: const Value(20000),
        costPrice: const Value(10000),
        currentStock: const Value(30),
        categoryId: Value(catId),
        isActive: const Value(true),
      ),
    );
    productB = (await productRepo.getProductById(prodBId))!;

    posController = PosController();
    Get.put<PosController>(posController);

    // Tunggu stream binding produk terisi
    await pumpEventQueue();
    posController.allProducts.assignAll([productA, productB]);
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Koreksi Scan Kamera & Keranjang POS Tests', () {
    test('1. Satu event deteksi ganda untuk kode yang sama hanya menambah satu kali (cooldown)', () async {
      expect(posController.cartItems, isEmpty);

      // Event deteksi 1
      scannerService.simulateScan('899000111');
      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 1);
      expect(posController.totalItemsQty, 1);

      // Event deteksi 2 untuk kode yang sama dalam selang 200 ms (bounce ganda)
      fakeTime = fakeTime.add(const Duration(milliseconds: 200));
      scannerService.simulateScan('899000111');

      // Cooldown 1 detik pada ScannerService menolak deteksi ganda ini
      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 1, reason: 'Qty tidak boleh bertambah jadi 2 karena jeda < 1s');
      expect(posController.totalItemsQty, 1);
    });

    test('2. Dua kode berbeda menghasilkan dua baris keranjang terpisah', () async {
      expect(posController.cartItems, isEmpty);

      // Scan produk A
      scannerService.simulateScan('899000111');
      expect(posController.cartItems.length, 1);

      // Scan produk B (berbeda kode) langsung diproses tanpa terhambat cooldown
      fakeTime = fakeTime.add(const Duration(milliseconds: 100));
      scannerService.simulateScan('899000222');

      expect(posController.cartItems.length, 2);
      expect(posController.cartItems[0].product.id, productA.id);
      expect(posController.cartItems[0].qty.value, 1);
      expect(posController.cartItems[0].subtotal, 15000);

      expect(posController.cartItems[1].product.id, productB.id);
      expect(posController.cartItems[1].qty.value, 1);
      expect(posController.cartItems[1].subtotal, 20000);

      expect(posController.totalItemsQty, 2);
      expect(posController.finalTotalAmount, 35000);
    });

    test('3. Cooldown service tidak memblokir scan HID barang sama setelah jeda wajar (> 1 detik)', () async {
      expect(posController.cartItems, isEmpty);

      // Scan pertama
      scannerService.simulateScan('899000111');
      expect(posController.cartItems.first.qty.value, 1);

      // Kasir scan barang yang sama setelah jeda 1.2 detik
      fakeTime = fakeTime.add(const Duration(milliseconds: 1200));
      scannerService.simulateScan('899000111');

      // Barang sama bertambah qty-nya di baris yang sama
      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 2);
      expect(posController.totalItemsQty, 2);
      expect(posController.finalTotalAmount, 30000);
    });

    test('4. Dialog kuantitas (addCartItemWithQty) menambah qty sesuai input', () async {
      expect(posController.cartItems, isEmpty);

      // Simulasikan penambahan kuantitas 5 melalui dialog scan kamera
      posController.addCartItemWithQty(productA, 5);

      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 5);
      expect(posController.cartItems.first.subtotal, 75000);
      expect(posController.totalItemsQty, 5);
      expect(posController.finalTotalAmount, 75000);

      // Tambah lagi 3 pada produk yang sama
      posController.addCartItemWithQty(productA, 3);
      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 8);
      expect(posController.totalItemsQty, 8);
      expect(posController.finalTotalAmount, 120000);
    });

    test('5. Validasi batas stok pada addCartItemWithQty jika allowNegativeStock false', () async {
      posController.allowNegativeStock.value = false;

      // Produk B stok hanya 30. Tambah 35 harus ditolak
      posController.addCartItemWithQty(productB, 35);
      expect(posController.cartItems, isEmpty);

      // Tambah 25 berhasil
      posController.addCartItemWithQty(productB, 25);
      expect(posController.cartItems.length, 1);
      expect(posController.cartItems.first.qty.value, 25);
    });
  });
}
