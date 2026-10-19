import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/audit_dao.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/purchase_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/stock_dao.dart';
import 'package:pos_me/app/data/local/daos/supplier_dao.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/purchase_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/supplier_repository.dart';
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
  late SupplierDao supplierDao;
  late PurchaseDao purchaseDao;
  late StockDao stockDao;
  late AuditDao auditDao;
  late RoleDao roleDao;

  late ProductRepository productRepo;
  late SupplierRepository supplierRepo;
  late StockRepository stockRepo;
  late PurchaseRepository purchaseRepo;
  late AuditRepository auditRepo;
  late RoleRepository roleRepo;

  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;

  setUp(() async {
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());

    productDao = db.productDao;
    supplierDao = db.supplierDao;
    purchaseDao = db.purchaseDao;
    stockDao = db.stockDao;
    auditDao = db.auditDao;
    roleDao = db.roleDao;

    auditRepo = AuditRepository(auditDao);
    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService, permanent: true);

    entitlementProvider = MockEntitlementProvider(Tier.semi);
    featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate, permanent: true);

    final storeDao = db.storeDao;
    final userDao = db.userDao;
    final storeRepo = StoreRepository(storeDao);
    final userRepo = UserRepository(userDao);
    final authService = AuthService(storeRepo, userRepo);
    Get.put<AuthService>(authService, permanent: true);

    roleRepo = RoleRepository(roleDao);
    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService, permanent: true);

    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko Test'),
        mode: drift.Value('solo'),
        requireLogin: drift.Value(false),
      ),
    );
    await RoleSeeder.seedDefaultRoles(roleRepo);
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('owner_test'),
        displayName: const drift.Value('Owner Test'),
        roleId: drift.Value(ownerRole!.id),
      ),
    );
    authService.currentUser.value = await userRepo.getUserById(ownerId);
    await authService.refreshState();
    await permissionService.refreshPermissions();

    productRepo = ProductRepository(productDao, featureGate: featureGate);
    supplierRepo = SupplierRepository(supplierDao);
    stockRepo = StockRepository(db, stockDao, productDao);
    purchaseRepo = PurchaseRepository(
      db,
      purchaseDao,
      stockRepo,
      productDao,
      productRepo,
      supplierDao,
    );
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 11: Supplier CRUD & Validation Tests', () {
    test('Supplier CRUD: nama wajib, unik tanpa case-sensitive, delete ditolak jika ada pembelian', () async {
      // 1. Tambah supplier
      final s1 = await supplierRepo.createSupplier(
        name: 'PT Sumber Berkah',
        phone: '0812345678',
        address: 'Jakarta',
      );
      expect(s1.name, 'PT Sumber Berkah');

      // 2. Tambah supplier nama sama beda huruf besar/kecil harus ditolak
      expect(
        () => supplierRepo.createSupplier(name: 'pt sumber berkah'),
        throwsA(isA<AppException>()),
      );

      // 3. Update nama supplier ke yang sudah ada ditolak
      final s2 = await supplierRepo.createSupplier(name: 'CV Jaya Abadi');
      expect(
        () => supplierRepo.updateSupplier(id: s2.id, name: 'PT SUMBER BERKAH'),
        throwsA(isA<AppException>()),
      );

      // 4. Hapus supplier tanpa transaksi berhasil
      await supplierRepo.deleteSupplier(s2.id);
      expect(await supplierRepo.getSupplierById(s2.id), isNull);

      // 5. Tambah produk & pembelian untuk s1
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Kopi Bubuk'),
          costPrice: drift.Value(5000),
          sellPrice: drift.Value(8000),
          currentStock: drift.Value(0),
        ),
      );

      await purchaseRepo.receive(
        supplierId: s1.id,
        items: [
          PurchaseItemInput(productId: pId, qty: 10, costPrice: 5000),
        ],
      );

      // 6. Hapus supplier yang memiliki transaksi pembelian WAJIB DITOLAK
      expect(
        () => supplierRepo.deleteSupplier(s1.id),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('Prompt 11: Purchase Operations, Stock & CostPrice Tests', () {
    test('1. Pembelian menambah stok produk dan memperbarui costPrice produk sesuai toggle', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Minyak Goreng 1L'),
          costPrice: drift.Value(14000),
          sellPrice: drift.Value(17000),
          currentStock: drift.Value(5),
        ),
      );

      final supplier = await supplierRepo.createSupplier(name: 'Grosir Minyak');

      // Pembelian dengan harga baru 15.000 dan toggle updateCostPrice = true
      final purchase = await purchaseRepo.receive(
        supplierId: supplier.id,
        refNo: 'FAKTUR-001',
        items: [
          PurchaseItemInput(
            productId: pId,
            qty: 10,
            costPrice: 15000,
            updateProductCost: true,
          ),
        ],
        updateCostPrice: true,
      );

      expect(purchase.total, 150000);
      expect(purchase.status, 'received');

      // Cek stok produk: 5 + 10 = 15
      final productAfter = await productDao.getProductById(pId);
      expect(productAfter?.currentStock, 15);
      expect(productAfter?.costPrice, 15000); // costPrice terupdate

      // Cek kartu stok / stock_movements
      final movements = await stockDao.getMovementsByProduct(pId);
      expect(movements.any((m) => m.type == 'purchase' && m.qtyChange == 10), isTrue);
    });

    test('2. Cancel pembelian mengembalikan stok via movement adjustment negatif', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Gula Pasir 1kg'),
          costPrice: drift.Value(12000),
          sellPrice: drift.Value(15000),
          currentStock: drift.Value(10),
        ),
      );

      final purchase = await purchaseRepo.receive(
        items: [
          PurchaseItemInput(productId: pId, qty: 5, costPrice: 12000),
        ],
      );

      var product = await productDao.getProductById(pId);
      expect(product?.currentStock, 15);

      // Batalkan pembelian
      final cancelled = await purchaseRepo.cancelPurchase(
        purchaseId: purchase.id,
        reason: 'Salah kirim faktur supplier',
      );

      expect(cancelled.status, 'cancelled');

      product = await productDao.getProductById(pId);
      expect(product?.currentStock, 10); // Stok kembali ke 10

      // Cek movement adjustment negatif
      final movements = await stockDao.getMovementsByProduct(pId);
      expect(movements.any((m) => m.type == 'adjustment' && m.qtyChange == -5), isTrue);
    });

    test('3. Cancel pembelian ditolak jika stok saat ini kurang untuk dibalikkan', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Beras 5kg'),
          costPrice: drift.Value(60000),
          sellPrice: drift.Value(75000),
          currentStock: drift.Value(0),
        ),
      );

      // Beli 10 pcs -> stok jadi 10
      final purchase = await purchaseRepo.receive(
        items: [
          PurchaseItemInput(productId: pId, qty: 10, costPrice: 60000),
        ],
      );

      // Simulasikan penjualan 8 pcs keluar -> sisa stok tinggal 2 pcs
      await stockRepo.applyMovement(
        productId: pId,
        type: 'sale',
        qtyChange: -8,
      );

      final product = await productDao.getProductById(pId);
      expect(product?.currentStock, 2);

      // Coba cancel 10 pcs -> stok fisik hanya 2, harus ditolak!
      expect(
        () => purchaseRepo.cancelPurchase(
          purchaseId: purchase.id,
          reason: 'Retur faktur batal',
        ),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.message.contains('tidak mencukupi untuk dibalikkan')),
        ),
      );
    });

    test('4. Cancel pembelian dua kali ditolak', () async {
      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Sabun Cuci'),
          costPrice: drift.Value(3000),
          sellPrice: drift.Value(5000),
          currentStock: drift.Value(5),
        ),
      );

      final purchase = await purchaseRepo.receive(
        items: [
          PurchaseItemInput(productId: pId, qty: 5, costPrice: 3000),
        ],
      );

      // Cancel pertama sukses
      await purchaseRepo.cancelPurchase(
        purchaseId: purchase.id,
        reason: 'Barang reject pabrik',
      );

      // Cancel kedua harus ditolak
      expect(
        () => purchaseRepo.cancelPurchase(
          purchaseId: purchase.id,
          reason: 'Coba cancel lagi',
        ),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.message.contains('sudah dibatalkan sebelumnya')),
        ),
      );
    });

    test('5. Tier Gratis ditolak membuat pembelian di level repository', () async {
      // Ubah tier ke Free (Gratis)
      entitlementProvider.currentMockTier = Tier.free;
      featureGate.tier.value = Tier.free;

      final pId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Produk Tier Free'),
          costPrice: drift.Value(1000),
          sellPrice: drift.Value(2000),
          currentStock: drift.Value(0),
        ),
      );

      expect(
        () => purchaseRepo.receive(
          items: [
            PurchaseItemInput(productId: pId, qty: 1, costPrice: 1000),
          ],
        ),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.code == 'FEATURE_LOCKED'),
        ),
      );
    });

    test('6. Produk nonaktif atau terkunci tier ditolak ditambahkan ke pembelian', () async {
      // Produk nonaktif
      final inactiveId = await productDao.insertProduct(
        const ProductsCompanion(
          name: drift.Value('Produk Kadaluarsa Nonaktif'),
          costPrice: drift.Value(1000),
          sellPrice: drift.Value(2000),
          isActive: drift.Value(false),
          currentStock: drift.Value(0),
        ),
      );

      expect(
        () => purchaseRepo.receive(
          items: [
            PurchaseItemInput(productId: inactiveId, qty: 5, costPrice: 1000),
          ],
        ),
        throwsA(
          predicate((e) =>
              e is AppException &&
              e.message.contains('sedang nonaktif')),
        ),
      );
    });
  });
}

