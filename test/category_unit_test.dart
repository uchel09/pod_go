import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/category_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/unit_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/master_data_seeder.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/modules/categories/controllers/categories_controller.dart';
import 'package:pos_me/app/modules/units/controllers/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository categoryRepo;
  late UnitRepository unitRepo;
  late ProductRepository productRepo;
  late RoleRepository roleRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late AuditRepository auditRepo;

  late CategoriesController categoriesController;
  late UnitsController unitsController;
  late AuthService authService;
  late PermissionService permissionService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'mock-device-cat-unit',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    categoryRepo = CategoryRepository(db.categoryDao);
    unitRepo = UnitRepository(db.unitDao);
    productRepo = ProductRepository(db.productDao);
    roleRepo = RoleRepository(db.roleDao);
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    auditRepo = AuditRepository(db.auditDao);

    Get.put<AppDatabase>(db);
    Get.put<CategoryRepository>(categoryRepo);
    Get.put<UnitRepository>(unitRepo);
    Get.put<ProductRepository>(productRepo);
    Get.put<RoleRepository>(roleRepo);
    Get.put<StoreRepository>(storeRepo);
    Get.put<UserRepository>(userRepo);
    Get.put<AuditRepository>(auditRepo);

    await Get.putAsync(() => DeviceIdService().init());
    Get.put<AuditService>(AuditService(auditRepo));

    authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService);

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService);

    // Setup Solo store with Owner agar permission productEdit aktif secara default
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Test'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner_test'),
        displayName: const Value('Owner Test'),
        roleId: Value(ownerRole!.id),
      ),
    );
    authService.currentUser.value = await userRepo.getUserById(ownerId);
    await authService.refreshState();
    await permissionService.refreshPermissions();

    categoriesController = CategoriesController();
    Get.put<CategoriesController>(categoriesController);

    unitsController = UnitsController();
    Get.put<UnitsController>(unitsController);
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('MasterDataSeeder Tests', () {
    test('MasterDataSeeder menyemai kategori Umum dan 6 satuan awal secara idempotent', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);

      final cats = await categoryRepo.getAllCategories();
      expect(cats.length, 1);
      expect(cats.first.name, 'Umum');

      final units = await unitRepo.getAllUnits();
      expect(units.length, 6);
      expect(units.map((u) => u.symbol).toSet(), containsAll(['pcs', 'kg', 'gram', 'liter', 'dus', 'pack']));

      // Jalankan ulang seeder: jumlah tidak boleh bertambah
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      final catsSecond = await categoryRepo.getAllCategories();
      final unitsSecond = await unitRepo.getAllUnits();
      expect(catsSecond.length, 1);
      expect(unitsSecond.length, 6);
    });
  });

  group('Kategori CRUD & Validasi Tests', () {
    test('Tambah kategori: validasi nama wajib dan validasi unik (case-insensitive)', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      await pumpEventQueue();

      // 1. Tambah kategori normal
      await categoriesController.addCategory('  Makanan Ringan  ');
      await pumpEventQueue();

      final created = await categoryRepo.getCategoryByName('Makanan Ringan');
      expect(created, isNotNull);
      expect(created!.name, 'Makanan Ringan');

      // 2. Tambah kategori dengan nama kosong -> gagal
      expect(
        () => categoriesController.addCategory('   '),
        throwsA(isA<AppException>()),
      );

      // 3. Tambah kategori duplikat case-insensitive ("makanan ringan" vs "Makanan Ringan") -> gagal
      expect(
        () => categoriesController.addCategory('makanan ringan'),
        throwsA(isA<AppException>()),
      );

      // 4. Tambah kategori duplikat dengan "UMUM" -> gagal
      expect(
        () => categoriesController.addCategory('UMUM'),
        throwsA(isA<AppException>()),
      );
    });

    test('Edit kategori: validasi unik nama terhadap kategori lain', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      await categoriesController.addCategory('Minuman');
      await pumpEventQueue();

      final minCat = (await categoryRepo.getCategoryByName('Minuman'))!;

      // Update normal
      await categoriesController.updateCategory(minCat.id, 'Minuman Dingin');
      await pumpEventQueue();
      final updated = await categoryRepo.getCategoryById(minCat.id);
      expect(updated?.name, 'Minuman Dingin');

      // Update dengan nama yang sudah dipakai kategori lain ("Umum") -> gagal
      expect(
        () => categoriesController.updateCategory(minCat.id, 'umum'),
        throwsA(isA<AppException>()),
      );
    });

    test('Hapus kategori: ditolak bila masih dipakai oleh produk', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      await categoriesController.addCategory('Elektronik');
      await pumpEventQueue();

      final cat = (await categoryRepo.getCategoryByName('Elektronik'))!;
      final unit = (await unitRepo.getUnitBySymbol('pcs'))!;

      // 1. Masukkan produk yang memakai kategori ini
      await productRepo.insertProduct(
        ProductsCompanion(
          name: const Value('Kabel USB'),
          categoryId: Value(cat.id),
          unitId: Value(unit.id),
          costPrice: const Value(15000),
          sellPrice: const Value(25000),
          currentStock: const Value(10),
          minStock: const Value(2),
        ),
      );

      // 2. Coba hapus kategori -> harus ditolak dengan kode 'CATEGORY_IN_USE'
      expect(
        () => categoriesController.deleteCategory(cat),
        throwsA(predicate((e) => e is AppException && e.code == 'CATEGORY_IN_USE')),
      );

      // Kategori tetap ada di DB
      final catStillExists = await categoryRepo.getCategoryById(cat.id);
      expect(catStillExists, isNotNull);

      // 3. Hapus produk terlebih dahulu, baru hapus kategori -> berhasil
      final prod = (await productRepo.getAllProducts()).first;
      await productRepo.deleteProduct(prod.id);

      await categoriesController.deleteCategory(cat);
      final catDeleted = await categoryRepo.getCategoryById(cat.id);
      expect(catDeleted, isNull);
    });
  });

  group('Satuan CRUD & Validasi Tests', () {
    test('Tambah satuan: validasi nama & simbol unik (case-insensitive)', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      await pumpEventQueue();

      // 1. Tambah satuan normal
      await unitsController.addUnit('Meter', 'm');
      await pumpEventQueue();

      final created = await unitRepo.getUnitBySymbol('m');
      expect(created, isNotNull);
      expect(created!.name, 'Meter');

      // 2. Tambah dengan simbol duplikat ("PCS" vs "pcs") -> gagal
      expect(
        () => unitsController.addUnit('Pieces Baru', 'PCS'),
        throwsA(isA<AppException>()),
      );

      // 3. Tambah dengan nama duplikat ("kilogram") -> gagal
      expect(
        () => unitsController.addUnit('kilogram', 'kg2'),
        throwsA(isA<AppException>()),
      );
    });

    test('Hapus satuan: ditolak bila masih dipakai produk', () async {
      await MasterDataSeeder.seed(categoryRepo, unitRepo);
      final unitPcs = (await unitRepo.getUnitBySymbol('pcs'))!;
      final catUmum = (await categoryRepo.getCategoryByName('Umum'))!;

      // Pasang produk dengan satuan pcs
      await productRepo.insertProduct(
        ProductsCompanion(
          name: const Value('Buku Tulis'),
          categoryId: Value(catUmum.id),
          unitId: Value(unitPcs.id),
          costPrice: const Value(3000),
          sellPrice: const Value(5000),
          currentStock: const Value(20),
          minStock: const Value(5),
        ),
      );

      // Coba hapus satuan pcs -> ditolak
      expect(
        () => unitsController.deleteUnit(unitPcs),
        throwsA(predicate((e) => e is AppException && e.code == 'UNIT_IN_USE')),
      );

      // Satuan tetap ada
      final stillExists = await unitRepo.getUnitById(unitPcs.id);
      expect(stillExists, isNotNull);
    });
  });

  group('RBAC Hak Akses Kategori & Satuan Tests', () {
    test('Role tanpa product.edit (misal Kasir) ditolak memodifikasi kategori dan satuan', () async {
      // Ubah store ke Mode Tim
      await storeRepo.updateStore(
        const StoresCompanion(
          id: Value(1),
          name: Value('Toko Test'),
          mode: Value('team'),
          requireLogin: Value(true),
        ),
      );
      await authService.refreshState();

      // Login sebagai Kasir (hanya memiliki product.view, tanpa product.edit)
      final kasirRole = await roleRepo.getRoleByName('Kasir');
      final kasirId = await userRepo.insertUser(
        UsersCompanion(
          username: const Value('kasir_test'),
          displayName: const Value('Kasir Test'),
          roleId: Value(kasirRole!.id),
        ),
      );
      authService.currentUser.value = await userRepo.getUserById(kasirId);
      await permissionService.refreshPermissions();

      expect(categoriesController.canView, isTrue);
      expect(categoriesController.canEdit, isFalse);
      expect(unitsController.canEdit, isFalse);

      // Operasi tulis kategori harus throw AppException akses ditolak
      expect(
        () => categoriesController.addCategory('Kategori Ilegal'),
        throwsA(isA<AppException>()),
      );

      // Operasi tulis satuan harus throw AppException akses ditolak
      expect(
        () => unitsController.addUnit('Satuan Ilegal', 'stl'),
        throwsA(isA<AppException>()),
      );
    });
  });
}

