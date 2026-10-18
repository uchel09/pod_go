import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/category_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/unit_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/modules/products/controllers/products_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late ProductRepository productRepo;
  late CategoryRepository categoryRepo;
  late UnitRepository unitRepo;
  late StockRepository stockRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late LicenseRepository licenseRepo;
  late AuditRepository auditRepo;
  late SettingsRepository settingsRepo;

  late FeatureGate featureGate;
  late AuthService authService;
  late PermissionService permissionService;
  late ProductsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'mock-device-product-test',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );
    categoryRepo = CategoryRepository(db.categoryDao);
    unitRepo = UnitRepository(db.unitDao);
    stockRepo = StockRepository(db, db.stockDao, db.productDao);
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);
    settingsRepo = SettingsRepository(db.settingsDao);

    // Register into GetX DI
    Get.put<AppDatabase>(db);
    Get.put<ProductRepository>(productRepo);
    Get.put<CategoryRepository>(categoryRepo);
    Get.put<UnitRepository>(unitRepo);
    Get.put<StockRepository>(stockRepo);
    Get.put<StoreRepository>(storeRepo);
    Get.put<UserRepository>(userRepo);
    Get.put<RoleRepository>(roleRepo);
    Get.put<LicenseRepository>(licenseRepo);
    Get.put<AuditRepository>(auditRepo);
    Get.put<SettingsRepository>(settingsRepo);

    final entitlement = SimulatedEntitlementProvider(licenseRepo);
    Get.put<EntitlementProvider>(entitlement);

    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService);

    featureGate = FeatureGate(entitlement);
    Get.put<FeatureGate>(featureGate);
    await featureGate.init();

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService);

    authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService);

    // Setup Store & Roles
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Produk Barokah'),
        mode: Value('solo'),
        requireLogin: Value(false),
        scannerType: Value('1d'),
      ),
    );

    await RoleSeeder.seedDefaultRoles(roleRepo);
    final ownerRole = await roleRepo.getRoleByName('Owner');
    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Owner'),
        roleId: Value(ownerRole!.id),
      ),
    );

    await authService.init();
    await permissionService.init();

    controller = Get.put<ProductsController>(ProductsController());
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Batas Tier Produk Tests', () {
    test('Tier Gratis menolak produk aktif ke-11 dan membuka kuota saat produk dinonaktifkan', () async {
      expect(featureGate.tier.value, Tier.free);
      expect(featureGate.productLimit, 10);

      // 1. Tambah 10 produk aktif (sukses)
      for (int i = 1; i <= 10; i++) {
        final id = await productRepo.createProduct(
          ProductsCompanion.insert(
            name: 'Produk $i',
            sellPrice: const Value(10000),
            isActive: const Value(true),
          ),
        );
        expect(id, isPositive);
      }

      final activeCount = await productRepo.countActiveProducts();
      expect(activeCount, 10);

      // 2. Coba tambah produk ke-11 -> harus melempar LimitReachedException
      expect(
        () => productRepo.createProduct(
          ProductsCompanion.insert(
            name: 'Produk 11',
            sellPrice: const Value(15000),
            isActive: const Value(true),
          ),
        ),
        throwsA(isA<LimitReachedException>()),
      );

      // 3. Menonaktifkan 1 produk -> membuka kuota
      final products = await productRepo.getAllProducts();
      final firstProduct = products.first;
      await productRepo.setProductActive(firstProduct.id, false);

      final newActiveCount = await productRepo.countActiveProducts();
      expect(newActiveCount, 9);

      // 4. Tambah produk baru sekarang berhasil
      final newProdId = await productRepo.createProduct(
        ProductsCompanion.insert(
          name: 'Produk Baru Pengganti',
          sellPrice: const Value(20000),
          isActive: const Value(true),
        ),
      );
      expect(newProdId, isPositive);
      expect(await productRepo.countActiveProducts(), 10);
    });

    test('Tier turun: produk ke-11 ke atas terkunci (read-only lock)', () async {
      // 1. Upgrade ke Semi-Premium (unlimited)
      await licenseRepo.insertLicense(
        LicensesCompanion(
          tier: const Value('semi'),
          source: const Value('simulated'),
          status: const Value('active'),
          issuedAt: Value(DateTime.now()),
        ),
      );
      await featureGate.init();
      expect(featureGate.tier.value, Tier.semi);
      expect(featureGate.productLimit, isNull);

      // 2. Tambah 13 produk
      final createdProducts = <Product>[];
      for (int i = 1; i <= 13; i++) {
        final id = await productRepo.createProduct(
          ProductsCompanion.insert(
            name: 'Barang $i',
            sellPrice: const Value(10000),
            isActive: const Value(true),
            createdAt: Value(DateTime.now().add(Duration(seconds: i))),
          ),
        );
        final p = await productRepo.getProductById(id);
        createdProducts.add(p!);
      }

      expect(await productRepo.countActiveProducts(), 13);

      // 3. Lisensi turun kembali ke Gratis (expired)
      await licenseRepo.insertLicense(
        LicensesCompanion(
          tier: const Value('free'),
          source: const Value('simulated'),
          status: const Value('active'),
          issuedAt: Value(DateTime.now()),
        ),
      );
      await featureGate.init();
      expect(featureGate.tier.value, Tier.free);
      expect(featureGate.productLimit, 10);

      // 4. Periksa status kunci: 10 pertama tidak terkunci, 11-13 terkunci
      final lockedIds = await productRepo.getLockedProductIds();
      expect(lockedIds.length, 3);

      for (int i = 0; i < 10; i++) {
        final isLocked = await productRepo.isProductLockedByTier(createdProducts[i]);
        expect(isLocked, isFalse, reason: 'Produk ke-${i + 1} harus terbuka');
      }

      for (int i = 10; i < 13; i++) {
        final isLocked = await productRepo.isProductLockedByTier(createdProducts[i]);
        expect(isLocked, isTrue, reason: 'Produk ke-${i + 1} harus terkunci');
      }

      // 5. Update produk terkunci lewat Controller ditolak
      final lockedProduct = createdProducts[11];
      expect(
        () => controller.updateProductData(
          oldProduct: lockedProduct,
          name: 'Ubah Nama Terkunci',
          sellPrice: 20000,
        ),
        throwsA(
          predicate((e) => e is AppException && e.code == 'PRODUCT_LOCKED_BY_TIER'),
        ),
      );
    });
  });

  group('Kode Internal & Barcode Tests', () {
    test('Generate kode internal menghasilkan format P + 6 digit unik tanpa duplikat', () async {
      final code1 = await productRepo.generateInternalCode();
      expect(code1['code'], 'P000001');
      expect(code1['codeType'], 'internal_code128');

      // Simpan produk dengan kode tersebut
      await productRepo.createProduct(
        ProductsCompanion.insert(
          name: 'Produk P000001',
          barcode: Value(code1['code']),
          internalCode: Value(code1['code']),
          sellPrice: const Value(5000),
        ),
      );

      // Generate berikutnya harus P000002
      final code2 = await productRepo.generateInternalCode();
      expect(code2['code'], 'P000002');

      // Jika sengaja ada produk manual dengan P000003
      await productRepo.createProduct(
        ProductsCompanion.insert(
          name: 'Produk P000003 Manual',
          barcode: const Value('P000003'),
          internalCode: const Value('P000003'),
          sellPrice: const Value(5000),
        ),
      );

      // Generate berikutnya setelah P000002 harus melompati P000003 ke P000004
      await productRepo.createProduct(
        ProductsCompanion.insert(
          name: 'Produk P000002',
          barcode: Value(code2['code']),
          internalCode: Value(code2['code']),
          sellPrice: const Value(5000),
        ),
      );

      final code4 = await productRepo.generateInternalCode();
      expect(code4['code'], 'P000004');
    });

    test('Validasi menolak barcode duplikat pada produk berbeda', () async {
      await controller.addProduct(
        name: 'Susu UHT Coklat',
        barcode: '8991234567890',
        sellPrice: 6500,
      );

      expect(
        () => controller.addProduct(
          name: 'Susu UHT Stroberi',
          barcode: '8991234567890',
          sellPrice: 6500,
        ),
        throwsA(
          predicate((e) => e is AppException && e.code == 'BARCODE_DUPLICATE'),
        ),
      );
    });
  });

  group('Stok Awal & Audit Trail Tests', () {
    test('Stok awal dicatat sebagai stock_movements adjustment secara otomatis', () async {
      final id = await controller.addProduct(
        name: 'Beras Premium 5kg',
        sellPrice: 75000,
        costPrice: 65000,
        initialStock: 25,
      );

      final product = await productRepo.getProductById(id);
      expect(product?.currentStock, 25);

      final movements = await stockRepo.getMovementsByProduct(id);
      expect(movements.length, 1);
      expect(movements.first.type, 'adjustment');
      expect(movements.first.qtyChange, 25);
    });

    test('Perubahan harga jual dan beli dicatat ke AuditService', () async {
      final id = await controller.addProduct(
        name: 'Minyak Goreng 2L',
        sellPrice: 35000,
        costPrice: 30000,
      );

      final product = (await productRepo.getProductById(id))!;

      await controller.updateProductData(
        oldProduct: product,
        name: 'Minyak Goreng 2L',
        sellPrice: 38000, // Harga naik
        costPrice: 32000,
      );

      final auditLogs = await auditRepo.getAllLogs();
      final priceChangeLog = auditLogs.firstWhereOrNull((l) => l.action == 'product.price_change');
      expect(priceChangeLog, isNotNull);
      expect(priceChangeLog?.entityId, id);
    });

    test('updateProductData dengan tambah stok (+) menambah stok dan mencatat movement', () async {
      final id = await controller.addProduct(
        name: 'Gula Pasir 1kg',
        sellPrice: 15000,
        initialStock: 10,
      );

      var product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 10);

      await controller.updateProductData(
        oldProduct: product,
        name: 'Gula Pasir 1kg',
        sellPrice: 15000,
        stockActionMode: 'add',
        stockDelta: 15,
        stockNote: 'Restok supplier',
      );

      product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 25);

      final movements = await stockRepo.getMovementsByProduct(id);
      expect(movements.length, 2); // Initial stock (10) + Restok (15)
      expect(movements.last.qtyChange, 15);
      expect(movements.last.note, 'Restok supplier');
    });

    test('updateProductData dengan edit/set stok (=) menghitung selisih dan mengupdate stok', () async {
      final id = await controller.addProduct(
        name: 'Kopi Bubuk 250g',
        sellPrice: 20000,
        initialStock: 20,
      );

      var product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 20);

      // Set stok ke 12 (selisih -8)
      await controller.updateProductData(
        oldProduct: product,
        name: 'Kopi Bubuk 250g',
        sellPrice: 20000,
        stockActionMode: 'set',
        stockDelta: -8,
        stockNote: 'Opname fisik',
      );

      product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 12);

      final movements = await stockRepo.getMovementsByProduct(id);
      expect(movements.length, 2);
      expect(movements.last.qtyChange, -8);
      expect(movements.last.note, 'Opname fisik');
    });

    test('adjustStock langsung menambah dan mengubah stok dengan audit log', () async {
      final id = await controller.addProduct(
        name: 'Teh Celup Kotak',
        sellPrice: 8000,
        initialStock: 5,
      );

      var product = (await productRepo.getProductById(id))!;

      // Tambah stok 10 via adjustStock
      await controller.adjustStock(
        product: product,
        mode: 'add',
        qty: 10,
        note: 'Beli lagi',
      );

      product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 15);

      // Set stok ke 30 via adjustStock
      await controller.adjustStock(
        product: product,
        mode: 'set',
        qty: 30,
        note: 'Koreksi akhir bulan',
      );

      product = (await productRepo.getProductById(id))!;
      expect(product.currentStock, 30);

      final auditLogs = await auditRepo.getAllLogs();
      final stockLogs = auditLogs.where((l) => l.action == 'stock.adjustment').toList();
      expect(stockLogs.isNotEmpty, isTrue);
    });
  });

  group('RBAC Hak Akses Produk Tests', () {
    test('Role tanpa product.edit ditolak menambah atau mengubah produk', () async {
      // Ubah store ke Mode Tim & login sebagai Kasir
      await storeRepo.updateStore(
        const StoresCompanion(
          id: Value(1),
          name: Value('Toko Tim'),
          mode: Value('team'),
          requireLogin: Value(true),
        ),
      );
      await authService.refreshState();

      final kasirRole = await roleRepo.getRoleByName('Kasir');
      final kasirId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('kasir1'),
          displayName: const Value('Kasir Satu'),
          roleId: Value(kasirRole!.id),
        ),
      );
      authService.currentUser.value = await userRepo.getUserById(kasirId);
      await permissionService.refreshPermissions();

      expect(permissionService.can('product.edit'), isFalse);
      expect(controller.canEdit, isFalse);

      expect(
        () => controller.addProduct(
          name: 'Produk Ilegal',
          sellPrice: 10000,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
