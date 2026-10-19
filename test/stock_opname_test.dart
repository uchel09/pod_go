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
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/audit_dao.dart';
import 'package:pos_me/app/data/local/daos/opname_dao.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/stock_dao.dart';
import 'package:pos_me/app/data/local/daos/store_dao.dart';
import 'package:pos_me/app/data/local/daos/user_dao.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/opname_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
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
  late OpnameDao opnameDao;
  late StockDao stockDao;
  late AuditDao auditDao;
  late RoleDao roleDao;
  late StoreDao storeDao;
  late UserDao userDao;

  late StockRepository stockRepo;
  late OpnameRepository opnameRepo;
  late AuditRepository auditRepo;
  late RoleRepository roleRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;

  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;
  late AuthService authService;

  late Role ownerRole;
  late Role cashierRole;
  late User ownerUser;
  late User cashierUser;

  setUp(() async {
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());

    productDao = db.productDao;
    opnameDao = db.opnameDao;
    stockDao = db.stockDao;
    auditDao = db.auditDao;
    roleDao = db.roleDao;
    storeDao = db.storeDao;
    userDao = db.userDao;

    auditRepo = AuditRepository(auditDao);
    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService, permanent: true);

    entitlementProvider = MockEntitlementProvider(Tier.semi);
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate, permanent: true);

    storeRepo = StoreRepository(storeDao);
    userRepo = UserRepository(userDao);
    authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService, permanent: true);

    roleRepo = RoleRepository(roleDao);
    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService, permanent: true);

    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko Opname POS'),
        mode: drift.Value('solo'),
        requireLogin: drift.Value(false),
      ),
    );
    await RoleSeeder.seedDefaultRoles(roleRepo);

    ownerRole = (await roleRepo.getRoleByName('Owner'))!;
    cashierRole = (await roleRepo.getRoleByName('Kasir'))!;

    final oId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('owner_opname'),
        displayName: const drift.Value('Owner Opname'),
        roleId: drift.Value(ownerRole.id),
      ),
    );
    ownerUser = (await userRepo.getUserById(oId))!;

    final cId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('kasir_opname'),
        displayName: const drift.Value('Kasir Opname'),
        roleId: drift.Value(cashierRole.id),
      ),
    );
    cashierUser = (await userRepo.getUserById(cId))!;

    // Default: login as Owner
    authService.currentUser.value = ownerUser;
    await authService.refreshState();
    await permissionService.refreshPermissions();

    stockRepo = StockRepository(db, stockDao, productDao);
    opnameRepo = OpnameRepository(
      db,
      opnameDao,
      stockRepo,
      productDao,
    );
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 12: Stock Opname Comprehensive Tests', () {
    test('1. Finalisasi menyesuaikan stok sesuai selisih dan mencatat movement opname', () async {
      // 1. Tambah produk dengan stok 10
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Kopi Robusta 250g'),
          costPrice: drift.Value(15000),
          sellPrice: drift.Value(25000),
          currentStock: drift.Value(10),
          isActive: drift.Value(true),
        ),
      );

      // 2. Buat sesi opname
      final opname = await opnameRepo.createOpname(note: 'Hitung bulanan');
      expect(opname.status, 'draft');
      expect(opname.code.startsWith('OPN-'), isTrue);

      // 3. Masukkan hitungan fisik 14 (selisih +4)
      await opnameRepo.addOrIncrementItem(opnameId: opname.id, productId: pId, qty: 14);

      var detail = await opnameRepo.getOpnameDetail(opname.id);
      expect(detail?.items.length, 1);
      expect(detail?.items.first.countedQty, 14);
      expect(detail?.items.first.difference, 4);

      // 4. Finalisasi opname
      final finalized = await opnameRepo.finalize(opnameId: opname.id);
      expect(finalized.status, 'final');

      // 5. Cek stok produk di database berubah dari 10 menjadi 14
      final updatedProduct = await productDao.getProductById(pId);
      expect(updatedProduct?.currentStock, 14);

      // 6. Cek stock_movements bertipe 'opname'
      final movements = await stockDao.getMovementsByProduct(pId);
      final opnameMovement = movements.firstWhere((m) => m.type == 'opname');
      expect(opnameMovement.qtyChange, 4);
      expect(opnameMovement.refTable, 'stock_opnames');
      expect(opnameMovement.refId, opname.id);
    });

    test('2. Finalisasi dua kali pada sesi yang sama ditolak (ALREADY_FINALIZED)', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Susu UHT 1L'),
          costPrice: drift.Value(12000),
          sellPrice: drift.Value(18000),
          currentStock: drift.Value(5),
          isActive: drift.Value(true),
        ),
      );

      final opname = await opnameRepo.createOpname();
      await opnameRepo.addOrIncrementItem(opnameId: opname.id, productId: pId, qty: 7);
      await opnameRepo.finalize(opnameId: opname.id);

      // Finalisasi kedua harus gagal
      expect(
        () => opnameRepo.finalize(opnameId: opname.id),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.code == 'ALREADY_FINALIZED'),
        ),
      );
    });

    test('3. Item tanpa selisih (stok cocok) tidak membuat movement stok', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Teh Celup Kotak'),
          costPrice: drift.Value(5000),
          sellPrice: drift.Value(8000),
          currentStock: drift.Value(15),
          isActive: drift.Value(true),
        ),
      );

      final opname = await opnameRepo.createOpname();
      // Hitungan fisik persis sama dengan stok sistem: 15
      await opnameRepo.addOrIncrementItem(opnameId: opname.id, productId: pId, qty: 15);

      await opnameRepo.finalize(opnameId: opname.id);

      final product = await productDao.getProductById(pId);
      expect(product?.currentStock, 15);

      final movements = await stockDao.getMovementsByProduct(pId);
      expect(movements.where((m) => m.type == 'opname').isEmpty, isTrue);
    });

    test('4. Penjualan di tengah opname ditangani karena systemQty dihitung ulang saat finalisasi', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Biskuit Cokelat'),
          costPrice: drift.Value(4000),
          sellPrice: drift.Value(7000),
          currentStock: drift.Value(20),
          isActive: drift.Value(true),
        ),
      );

      // Buat opname & hitung fisik barang = 18 pcs
      final opname = await opnameRepo.createOpname();
      await opnameRepo.addOrIncrementItem(opnameId: opname.id, productId: pId, qty: 18);

      // Terjadi penjualan di tengah jalan: kasir menjual 5 pcs
      await stockRepo.applyMovement(
        productId: pId,
        type: 'sale',
        qtyChange: -5,
        note: 'Penjualan nota saat opname berjalan',
      );

      // Stok terkini produk di sistem sekarang adalah 15 (20 - 5)
      var currentP = await productDao.getProductById(pId);
      expect(currentP?.currentStock, 15);

      // Finalisasi opname:
      // Hitungan fisik adalah 18.
      // systemQty dihitung ulang menjadi 15.
      // Selisih menjadi 18 - 15 = +3.
      // Stok akhir setelah opname harus persis 18!
      await opnameRepo.finalize(opnameId: opname.id);

      currentP = await productDao.getProductById(pId);
      expect(currentP?.currentStock, 18);

      final movements = await stockDao.getMovementsByProduct(pId);
      final opMovement = movements.firstWhere((m) => m.type == 'opname');
      expect(opMovement.qtyChange, 3);
    });

    test('5. Opsi "tidak dihitung = 0" bekerja (dilewati vs diubah jadi 0)', () async {
      final pCounted = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Produk Dihitung Fisik'),
          costPrice: drift.Value(1000),
          sellPrice: drift.Value(2000),
          currentStock: drift.Value(10),
          isActive: drift.Value(true),
        ),
      );
      final pUncounted = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Produk Belum Dihitung'),
          costPrice: drift.Value(2000),
          sellPrice: drift.Value(4000),
          currentStock: drift.Value(7),
          isActive: drift.Value(true),
        ),
      );

      // Case A: Default (treatUncountedAsZero = false) -> produk belum dihitung TIDAK diubah
      final opnameA = await opnameRepo.createOpname();
      await opnameRepo.loadAllActiveProducts(opnameA.id);
      // Hanya hitung pCounted = 8 (selisih -2)
      await opnameRepo.addOrIncrementItem(opnameId: opnameA.id, productId: pCounted, qty: 8);

      await opnameRepo.finalize(opnameId: opnameA.id, treatUncountedAsZero: false);

      var p1 = await productDao.getProductById(pCounted);
      var p2 = await productDao.getProductById(pUncounted);
      expect(p1?.currentStock, 8); // Disesuaikan dari 10 ke 8
      expect(p2?.currentStock, 7); // TIDAK DIUBAH (tetap 7)

      // Case B: treatUncountedAsZero = true -> produk belum dihitung disesuaikan ke 0
      final opnameB = await opnameRepo.createOpname();
      await opnameRepo.loadAllActiveProducts(opnameB.id);
      await opnameRepo.addOrIncrementItem(opnameId: opnameB.id, productId: pCounted, qty: 8);

      await opnameRepo.finalize(opnameId: opnameB.id, treatUncountedAsZero: true);

      p1 = await productDao.getProductById(pCounted);
      p2 = await productDao.getProductById(pUncounted);
      expect(p1?.currentStock, 8);
      expect(p2?.currentStock, 0); // DIUBAH MENJADI 0
    });

    test('6. Tier Gratis ditolak membuat atau memfinalisasi opname di repository', () async {
      entitlementProvider.currentMockTier = Tier.free;
      featureGate.tier.value = Tier.free;

      expect(
        () => opnameRepo.createOpname(),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.code == 'FEATURE_LOCKED'),
        ),
      );
    });

    test('7. Role tanpa stock.opname ditolak mengakses repository opname', () async {
      // Ubah mode toko ke multi-user dan login sebagai Kasir
      await storeDao.updateStore(
        const StoresCompanion(
          id: drift.Value(1),
          name: drift.Value('Toko Opname POS'),
          mode: drift.Value('multi_user'),
          requireLogin: drift.Value(true),
        ),
      );
      authService.currentUser.value = cashierUser;
      await authService.refreshState();
      await permissionService.refreshPermissions();

      expect(permissionService.can('stock.opname'), isFalse);

      expect(
        () => opnameRepo.createOpname(),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.code == 'FORBIDDEN'),
        ),
      );
    });

    test('8. Draft opname boleh dihapus, sedangkan sesi final tidak dapat dihapus', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Sabun Cuci'),
          costPrice: drift.Value(3000),
          sellPrice: drift.Value(5000),
          currentStock: drift.Value(4),
          isActive: drift.Value(true),
        ),
      );

      final opname = await opnameRepo.createOpname();
      await opnameRepo.addOrIncrementItem(opnameId: opname.id, productId: pId, qty: 5);

      // Hapus draft -> sukses
      await opnameRepo.deleteOpname(opname.id);
      expect(await opnameRepo.getOpnameById(opname.id), isNull);

      // Buat opname baru lalu finalisasi
      final opnameFinal = await opnameRepo.createOpname();
      await opnameRepo.addOrIncrementItem(opnameId: opnameFinal.id, productId: pId, qty: 5);
      await opnameRepo.finalize(opnameId: opnameFinal.id);

      // Hapus sesi final -> ditolak
      expect(
        () => opnameRepo.deleteOpname(opnameFinal.id),
        throwsA(isA<AppException>()),
      );
    });
  });
}

