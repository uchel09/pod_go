import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/number_parser.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/audit_dao.dart';
import 'package:pos_me/app/data/local/daos/category_dao.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/settings_dao.dart';
import 'package:pos_me/app/data/local/daos/stock_dao.dart';
import 'package:pos_me/app/data/local/daos/store_dao.dart';
import 'package:pos_me/app/data/local/daos/supplier_dao.dart';
import 'package:pos_me/app/data/local/daos/unit_dao.dart';
import 'package:pos_me/app/data/local/daos/user_dao.dart';
import 'package:pos_me/app/data/models/import_models.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/import_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/data/services/import_template_service.dart';

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

  group('1. NumberParser Utility Tests (Tolerant Parsing)', () {
    test('Parsing integer murni dan angka ribuan berbagai format', () {
      expect(NumberParser.parseRupiah(12500), 12500);
      expect(NumberParser.parseRupiah('12500'), 12500);
      expect(NumberParser.parseRupiah('12.500'), 12500);
      expect(NumberParser.parseRupiah('Rp 12.500'), 12500);
      expect(NumberParser.parseRupiah('Rp. 12.500'), 12500);
      expect(NumberParser.parseRupiah('IDR 12.500'), 12500);
    });

    test('Parsing desimal dan koma sen', () {
      expect(NumberParser.parseRupiah('12.500,00'), 12500);
      expect(NumberParser.parseRupiah('12,500.00'), 12500);
      expect(NumberParser.parseRupiah('12.500,50'), 12501); // pembulatan ke atas
      expect(NumberParser.parseRupiah('12500,50'), 12501);
      expect(NumberParser.parseRupiah('12500,40'), 12500);
    });

    test('Parsing nilai nol, negatif, dan string invalid', () {
      expect(NumberParser.parseRupiah('0'), 0);
      expect(NumberParser.parseRupiah('-12.500'), -12500);
      expect(NumberParser.parseRupiah('(12.500)'), -12500);
      expect(NumberParser.parseRupiah(''), isNull);
      expect(NumberParser.parseRupiah(null), isNull);
      expect(NumberParser.parseRupiah('abc'), isNull);
    });
  });

  group('2. ImportTemplateService Tests', () {
    test('Template CSV dan XLSX Produk, Kategori, Supplier ter-generate dengan benar', () {
      // Produk
      final csvProduct = ImportTemplateService.generateCsv(ImportTemplateType.product);
      expect(csvProduct, contains('nama'));
      expect(csvProduct, contains('harga_jual'));
      expect(csvProduct, contains('harga_beli'));

      final xlsxProduct = ImportTemplateService.generateXlsx(ImportTemplateType.product);
      expect(xlsxProduct.isNotEmpty, isTrue);

      // Kategori
      final csvCategory = ImportTemplateService.generateCsv(ImportTemplateType.category);
      expect(csvCategory, contains('nama'));
      expect(csvCategory, contains('Makanan'));

      final xlsxCategory = ImportTemplateService.generateXlsx(ImportTemplateType.category);
      expect(xlsxCategory.isNotEmpty, isTrue);

      // Supplier
      final csvSupplier = ImportTemplateService.generateCsv(ImportTemplateType.supplier);
      expect(csvSupplier, contains('telepon'));
      expect(csvSupplier, contains('alamat'));

      final xlsxSupplier = ImportTemplateService.generateXlsx(ImportTemplateType.supplier);
      expect(xlsxSupplier.isNotEmpty, isTrue);
    });
  });

  group('3. ImportRepository Integration Tests', () {
    late AppDatabase db;
    late ProductDao productDao;
    late CategoryDao categoryDao;
    late UnitDao unitDao;
    late SupplierDao supplierDao;
    late SettingsDao settingsDao;
    late StockDao stockDao;
    late AuditDao auditDao;
    late RoleDao roleDao;
    late StoreDao storeDao;
    late UserDao userDao;

    late StockRepository stockRepo;
    late ProductRepository productRepo;
    late ImportRepository importRepo;
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
      productDao = db.productDao;
      categoryDao = db.categoryDao;
      unitDao = db.unitDao;
      supplierDao = db.supplierDao;
      settingsDao = db.settingsDao;
      stockDao = db.stockDao;
      auditDao = db.auditDao;
      roleDao = db.roleDao;
      storeDao = db.storeDao;
      userDao = db.userDao;

      stockRepo = StockRepository(db, stockDao, productDao);
      productRepo = ProductRepository(
        productDao,
        settingsDao: settingsDao,
        storeDao: storeDao,
      );
      auditRepo = AuditRepository(auditDao);
      roleRepo = RoleRepository(roleDao);
      storeRepo = StoreRepository(storeDao);
      userRepo = UserRepository(userDao);

      importRepo = ImportRepository(
        db: db,
        productDao: productDao,
        categoryDao: categoryDao,
        unitDao: unitDao,
        supplierDao: supplierDao,
        settingsDao: settingsDao,
        stockRepo: stockRepo,
        productRepo: productRepo,
      );

      // Default Tier: Semi (Import/Export diizinkan)
      entitlementProvider = MockEntitlementProvider(Tier.semi);
      featureGate = FeatureGate(entitlementProvider);
      await featureGate.init();
      Get.put<FeatureGate>(featureGate, permanent: true);

      // Audit Service
      Get.put<AuditService>(AuditService(auditRepo), permanent: true);

      // Seeder Role & User Owner
      await RoleSeeder.seedDefaultRoles(roleRepo);
      permissionService = PermissionService(roleRepo);
      Get.put<PermissionService>(permissionService, permanent: true);

      authService = AuthService(storeRepo, userRepo);
      Get.put<AuthService>(authService, permanent: true);

      await storeRepo.insertStore(
        const StoresCompanion(
          name: drift.Value('Toko Uji Import'),
          mode: drift.Value('solo'),
          requireLogin: drift.Value(false),
        ),
      );

      final ownerRole = (await roleRepo.getRoleByName('Owner'))!;
      final cashierRole = (await roleRepo.getRoleByName('Kasir'))!;

      final oId = await userRepo.insertUser(
        UsersCompanion(
          username: const drift.Value('owner_test'),
          displayName: const drift.Value('Owner Test'),
          roleId: drift.Value(ownerRole.id),
        ),
      );
      ownerUser = (await userRepo.getUserById(oId))!;

      final cId = await userRepo.insertUser(
        UsersCompanion(
          username: const drift.Value('cashier_no_import'),
          displayName: const drift.Value('Kasir No Import'),
          roleId: drift.Value(cashierRole.id),
        ),
      );
      cashierUser = (await userRepo.getUserById(cId))!;

      // Default login as Owner
      authService.currentUser.value = ownerUser;
      await authService.refreshState();
    });

    tearDown(() async {
      await db.close();
      Get.reset();
    });

    test('Validasi baris produk mendeteksi nama kosong, harga negatif, dan barcode duplikat', () async {
      final rows = [
        // Baris valid
        {
          'nama': 'Kopi Susu',
          'barcode': 'BR001',
          'sku': 'SKU001',
          'harga_jual': '15.000',
          'harga_beli': '10.000',
          'stok_awal': '20',
          'stok_minimum': '5',
        },
        // Baris nama kosong
        {
          'nama': '',
          'barcode': 'BR002',
          'harga_jual': '12.000',
        },
        // Baris harga jual negatif
        {
          'nama': 'Teh Manis',
          'barcode': 'BR003',
          'harga_jual': '-5.000',
        },
        // Baris barcode duplikat dalam file
        {
          'nama': 'Kopi Hitam',
          'barcode': 'BR001', // duplikat dari baris 1
          'harga_jual': '10.000',
        },
      ];

      final preview = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(mode: ImportMode.insertOnly),
      );

      expect(preview.length, 4);
      expect(preview[0].isValid, isTrue);

      expect(preview[1].isValid, isFalse);
      expect(preview[1].errors.any((e) => e.contains('Nama produk tidak boleh kosong')), isTrue);

      expect(preview[2].isValid, isFalse);
      expect(preview[2].errors.any((e) => e.contains('Harga jual tidak boleh bernilai negatif')), isTrue);

      expect(preview[3].isValid, isFalse);
      expect(preview[3].errors.any((e) => e.contains('terduplikasi dalam berkas')), isTrue);
    });

    test('Mode insertOnly menolak barcode yang sudah ada di database, mode upsert menandai sebagai update', () async {
      // Masukkan 1 produk ke database
      await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Indomie Goreng'),
          barcode: drift.Value('8999999001'),
          sellPrice: drift.Value(3500),
          currentStock: drift.Value(10),
        ),
      );

      final rows = [
        {
          'nama': 'Indomie Goreng Jumbo',
          'barcode': '8999999001',
          'harga_jual': '4.000',
        },
      ];

      // 1. Mode Insert Only -> Error duplikat DB
      final previewInsert = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(mode: ImportMode.insertOnly),
      );
      expect(previewInsert.first.isValid, isFalse);
      expect(previewInsert.first.errors.any((e) => e.contains('sudah ada di database')), isTrue);

      // 2. Mode Upsert -> Valid dan ditandai isUpdate = true
      final previewUpsert = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(mode: ImportMode.upsert),
      );
      expect(previewUpsert.first.isValid, isTrue);
      expect(previewUpsert.first.isUpdate, isTrue);
    });

    test('Eksekusi impor produk baru mencatat stok awal lewat StockRepository.applyMovement', () async {
      final rows = [
        {
          'nama': 'Biskuit Roma Kelapa',
          'barcode': '8991001100',
          'sku': 'ROM-01',
          'kategori': 'Makanan',
          'satuan': 'pack',
          'harga_beli': '7.500',
          'harga_jual': '10.000',
          'stok_awal': '50',
          'stok_minimum': '10',
        },
      ];

      final preview = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(autoCreateCategory: true, autoCreateUnit: true),
      );

      final summary = await importRepo.executeImportProducts(
        previewRows: preview,
        options: const ImportOptions(autoCreateCategory: true, autoCreateUnit: true),
        fileName: 'produk_test.csv',
      );

      expect(summary.successCount, 1);
      expect(summary.createdCount, 1);

      // Periksa produk tersimpan
      final product = await productDao.getProductByBarcode('8991001100');
      expect(product, isNotNull);
      expect(product!.name, 'Biskuit Roma Kelapa');
      expect(product.sellPrice, 10000);
      expect(product.costPrice, 7500);
      expect(product.currentStock, 50);

      // Periksa stock_movements bertipe adjustment tercatat
      final movements = await stockRepo.getMovementsByProduct(product.id);
      expect(movements.length, 1);
      expect(movements.first.type, 'adjustment');
      expect(movements.first.qtyChange, 50);
      expect(movements.first.note, contains('Stok awal'));

      // Periksa kategori dan satuan terbuat otomatis
      final cat = await categoryDao.getCategoryByName('Makanan');
      expect(cat, isNotNull);
      final unit = await unitDao.getUnitByName('pack');
      expect(unit, isNotNull);
    });

    test('Mode update: tidak menimpa stok jika correctStock false, mengoreksi stok jika correctStock true', () async {
      // Masukkan produk awal dengan currentStock 30
      final prodId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Susu UHT Coklat'),
          barcode: drift.Value('8992002200'),
          sellPrice: drift.Value(6000),
          currentStock: drift.Value(30),
        ),
      );

      final rows = [
        {
          'nama': 'Susu UHT Coklat 250ml',
          'barcode': '8992002200',
          'harga_jual': '6.500',
          'stok_awal': '45',
        },
      ];

      // 1. Update dengan correctStock: false
      final previewNoCorrect = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(mode: ImportMode.upsert, correctStock: false),
      );
      await importRepo.executeImportProducts(
        previewRows: previewNoCorrect,
        options: const ImportOptions(mode: ImportMode.upsert, correctStock: false),
        fileName: 'update_test.csv',
      );

      var updatedProd = await productDao.getProductById(prodId);
      expect(updatedProd!.name, 'Susu UHT Coklat 250ml');
      expect(updatedProd.sellPrice, 6500);
      expect(updatedProd.currentStock, 30); // Stok TIDAK berubah!

      // 2. Update dengan correctStock: true
      final previewWithCorrect = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(mode: ImportMode.upsert, correctStock: true),
      );
      await importRepo.executeImportProducts(
        previewRows: previewWithCorrect,
        options: const ImportOptions(mode: ImportMode.upsert, correctStock: true),
        fileName: 'update_test.csv',
      );

      updatedProd = await productDao.getProductById(prodId);
      expect(updatedProd!.currentStock, 45); // Stok terkoreksi dari 30 menjadi 45 (selisih +15)

      final movements = await stockRepo.getMovementsByProduct(prodId);
      expect(movements.isNotEmpty, isTrue);
      expect(movements.last.qtyChange, 15);
      expect(movements.last.type, 'adjustment');
    });

    test('Kode internal P000123 menaikkan internal_product_counter di settings agar tidak bentrok', () async {
      // Set awal counter di settings = 10
      await settingsDao.setSetting('internal_product_counter', '10');

      final rows = [
        {
          'nama': 'Barang Kode P123',
          'barcode': 'P000123',
          'harga_jual': '20.000',
        },
      ];

      final preview = await importRepo.validateProductRows(
        rows: rows,
        options: const ImportOptions(),
      );
      await importRepo.executeImportProducts(
        previewRows: preview,
        options: const ImportOptions(),
        fileName: 'internal_code_test.csv',
      );

      final counterStr = await settingsDao.getSetting('internal_product_counter');
      expect(counterStr, '124'); // Counter naik ke 123 + 1 = 124
    });

    test('Eksekusi batch performa (1.000 baris mock) berhasil diproses per batch 200 baris', () async {
      final largeRows = List.generate(1000, (i) {
        return {
          'nama': 'Produk Performa $i',
          'barcode': 'PERF_${i.toString().padLeft(4, '0')}',
          'harga_jual': '${(i + 1) * 1000}',
          'stok_awal': '10',
        };
      });

      final preview = await importRepo.validateProductRows(
        rows: largeRows,
        options: const ImportOptions(),
      );
      expect(preview.length, 1000);
      expect(preview.every((r) => r.isValid), isTrue);

      int progressCallbacks = 0;
      final summary = await importRepo.executeImportProducts(
        previewRows: preview,
        options: const ImportOptions(),
        fileName: 'large_1000.csv',
        onProgress: (processed, total, status) {
          progressCallbacks++;
        },
      );

      expect(summary.successCount, 1000);
      expect(summary.createdCount, 1000);
      expect(progressCallbacks, greaterThanOrEqualTo(5)); // minimal 5 batch x 200

      final totalProducts = await productDao.getAllProducts();
      expect(totalProducts.length, 1000);
    });

    test('Penolakan Tier Gratis: Melempar FEATURE_LOCKED', () async {
      // Ubah tier lisensi aktif ke Free
      entitlementProvider.currentMockTier = Tier.free;
      featureGate.tier.value = Tier.free;

      expect(
        () => importRepo.validateProductRows(
          rows: [
            {'nama': 'Produk X', 'harga_jual': '10.000'}
          ],
          options: const ImportOptions(),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );
    });

    test('Penolakan RBAC tanpa izin import.manage: Melempar FORBIDDEN', () async {
      // Ubah store ke multi_user dengan login wajib
      await storeDao.updateStore(
        const StoresCompanion(
          id: drift.Value(1),
          name: drift.Value('Toko Uji Import'),
          mode: drift.Value('multi_user'),
          requireLogin: drift.Value(true),
        ),
      );

      // Ganti login aktif ke Kasir tanpa izin import.manage
      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(
        () => importRepo.validateProductRows(
          rows: [
            {'nama': 'Produk Kasir', 'harga_jual': '10.000'}
          ],
          options: const ImportOptions(),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });
}
