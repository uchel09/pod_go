import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/sale_repository.dart';
import 'package:pos_me/app/data/repositories/sale_return_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late ProductRepository productRepo;
  late StockRepository stockRepo;
  late SaleRepository saleRepo;
  late SaleReturnRepository returnRepo;
  late ReportRepository reportRepo;
  late ReportDao reportDao;
  late LicenseRepository licenseRepo;
  late SettingsRepository settingsRepo;
  late AuditRepository auditRepo;
  late PermissionService permService;

  late User ownerUser;
  late User staffUser;
  late Product productA;
  late Product productB;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-return-dev-001',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    settingsRepo = SettingsRepository(db.settingsDao);
    stockRepo = StockRepository(db, db.stockDao, db.productDao);
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao);
    returnRepo = SaleReturnRepository(
      db,
      db.saleReturnDao,
      db.saleDao,
      stockRepo,
    );
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);

    reportDao = ReportDao(db);
    reportRepo = ReportRepository(reportDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);
    Get.put<ProductRepository>(productRepo, permanent: true);
    Get.put<StockRepository>(stockRepo, permanent: true);
    Get.put<SaleRepository>(saleRepo, permanent: true);
    Get.put<SaleReturnRepository>(returnRepo, permanent: true);
    Get.put<ReportRepository>(reportRepo, permanent: true);
    Get.put<LicenseRepository>(licenseRepo, permanent: true);
    Get.put<AuditRepository>(auditRepo, permanent: true);
    Get.put<SettingsRepository>(settingsRepo, permanent: true);

    final entitlementProvider = SimulatedEntitlementProvider(licenseRepo);
    final featureGate = FeatureGate(entitlementProvider);
    await featureGate.init();
    Get.put<FeatureGate>(featureGate, permanent: true);

    final auditService = AuditService(auditRepo);
    Get.put<AuditService>(auditService, permanent: true);

    permService = PermissionService(roleRepo);
    await permService.init();
    Get.put<PermissionService>(permService, permanent: true);

    final authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    // Setup toko
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Retur Berkah'),
        mode: Value('team'),
        requireLogin: Value(false),
      ),
    );

    // Setup Owner (memiliki izin pos.return)
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Owner Toko'),
        roleId: Value(ownerRole!.id),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    // Setup Kasir biasa (role Kasir tidak memiliki pos.return)
    final cashierRole = await roleRepo.getRoleByName('Kasir');
    final staffId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('staff_kasir'),
        displayName: const Value('Staff Kasir'),
        roleId: Value(cashierRole!.id),
      ),
    );
    staffUser = (await userRepo.getUserById(staffId))!;

    // Setup 2 Produk untuk pengujian
    final pAId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Produk A'),
        sellPrice: Value(50000),
        costPrice: Value(30000),
        currentStock: Value(50),
        isActive: Value(true),
      ),
    );
    productA = (await productRepo.getProductById(pAId))!;

    final pBId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Produk B'),
        sellPrice: Value(100000),
        costPrice: Value(60000),
        currentStock: Value(30),
        isActive: Value(true),
      ),
    );
    productB = (await productRepo.getProductById(pBId))!;

    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('PROMPT 19: Retur Sebagian (Per Item) Tests', () {
    test('1. Retur parsial item A dengan restock = true -> stok bertambah', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Checkout 5 pcs Produk A (stok 50 -> 45)
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 5,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 5 * productA.sellPrice),
        ],
      );

      final pAfterSale = await productRepo.getProductById(productA.id);
      expect(pAfterSale!.currentStock, equals(45));

      final saleItem = saleRes.items.first;

      // Retur 2 pcs dengan restock = true
      final returnResult = await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Salah beli varian',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productA.id,
              productName: productA.name,
              qty: 2,
              unitPrice: saleItem.price,
              costPrice: saleItem.costPrice,
              restock: true,
            ),
          ],
        ),
      );

      expect(returnResult.saleReturn.returnNo, startsWith('RTN-'));
      expect(returnResult.saleReturn.total, equals(100000));

      // Stok fisik harus bertambah 2 (45 -> 47)
      final pAfterReturn = await productRepo.getProductById(productA.id);
      expect(pAfterReturn!.currentStock, equals(47));

      // Verifikasi catatan pergerakan stok bertipe 'return'
      final movements = await stockRepo.getMovementsByProduct(productA.id);
      final returnMovement = movements.firstWhere((m) => m.type == 'return');
      expect(returnMovement.qtyChange, equals(2));
      expect(returnMovement.note, contains(returnResult.saleReturn.returnNo));
    });

    test('2. Retur parsial item B dengan restock = false -> stok TIDAK bertambah', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Checkout 5 pcs Produk B (stok 30 -> 25)
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productB.id,
            productName: productB.name,
            qty: 5,
            price: productB.sellPrice,
            costPrice: productB.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 5 * productB.sellPrice),
        ],
      );

      final pAfterSale = await productRepo.getProductById(productB.id);
      expect(pAfterSale!.currentStock, equals(25));

      final saleItem = saleRes.items.first;

      // Retur 2 pcs Produk B dengan restock = false (barang rusak)
      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Kemasan rusak bocor',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productB.id,
              productName: productB.name,
              qty: 2,
              unitPrice: saleItem.price,
              costPrice: saleItem.costPrice,
              restock: false,
            ),
          ],
        ),
      );

      // Stok fisik harus TETAP 25 (tidak bertambah)
      final pAfterReturn = await productRepo.getProductById(productB.id);
      expect(pAfterReturn!.currentStock, equals(25));

      // Pastikan tidak ada movement tipe 'return' untuk Produk B
      final movements = await stockRepo.getMovementsByProduct(productB.id);
      final hasReturnMovement = movements.any((m) => m.type == 'return');
      expect(hasReturnMovement, isFalse);
    });

    test('3. Retur dengan kuantitas melebihi yang dibeli ditolak (AppException)', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Checkout 3 pcs
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 3,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 3 * productA.sellPrice),
        ],
      );

      final saleItem = saleRes.items.first;

      // Coba retur 4 pcs -> Wajib melempar AppException
      expect(
        () async => await returnRepo.createReturn(
          CreateReturnInput(
            saleId: saleRes.sale.id,
            deviceId: 'dev-01',
            createdBy: ownerUser.id,
            refundMethod: 'cash',
            reason: 'Melebihi pembelian',
            items: [
              CreateReturnItemInput(
                saleItemId: saleItem.id,
                productId: productA.id,
                productName: productA.name,
                qty: 4,
                unitPrice: saleItem.price,
                costPrice: saleItem.costPrice,
                restock: true,
              ),
            ],
          ),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('4. Dua kali retur bertahap: total qty retur tidak boleh melebihi qty beli', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Checkout 5 pcs
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 5,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 5 * productA.sellPrice),
        ],
      );

      final saleItem = saleRes.items.first;

      // Retur pertama: 3 pcs (berhasil, sisa 2)
      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur tahap 1',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productA.id,
              productName: productA.name,
              qty: 3,
              unitPrice: saleItem.price,
              costPrice: saleItem.costPrice,
              restock: true,
            ),
          ],
        ),
      );

      // Cek sisa item yang dapat diretur lewat getReturnableItems
      final returnableAfterFirst = await returnRepo.getReturnableItems(saleRes.sale.id);
      expect(returnableAfterFirst.first.availableQty, equals(2));

      // Retur kedua: 2 pcs (berhasil, sisa 0)
      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur tahap 2',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productA.id,
              productName: productA.name,
              qty: 2,
              unitPrice: saleItem.price,
              costPrice: saleItem.costPrice,
              restock: true,
            ),
          ],
        ),
      );

      // Coba retur ketiga: 1 pc lagi -> Wajib ditolak
      expect(
        () async => await returnRepo.createReturn(
          CreateReturnInput(
            saleId: saleRes.sale.id,
            deviceId: 'dev-01',
            createdBy: ownerUser.id,
            refundMethod: 'cash',
            reason: 'Retur tahap 3 melebihi stok',
            items: [
              CreateReturnItemInput(
                saleItemId: saleItem.id,
                productId: productA.id,
                productName: productA.name,
                qty: 1,
                unitPrice: saleItem.price,
                costPrice: saleItem.costPrice,
                restock: true,
              ),
            ],
          ),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('5. Mutual exclusion: Transaksi yang ada retur tidak bisa di-void, dan sebaliknya', () async {
      AuthService.to.currentUser.value = ownerUser;

      // 5A. Transaksi dengan retur tidak bisa di-void
      final saleA = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 2,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 2 * productA.sellPrice),
        ],
      );

      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleA.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur sebelum coba void',
          items: [
            CreateReturnItemInput(
              saleItemId: saleA.items.first.id,
              productId: productA.id,
              productName: productA.name,
              qty: 1,
              unitPrice: saleA.items.first.price,
              costPrice: saleA.items.first.costPrice,
              restock: true,
            ),
          ],
        ),
      );

      // Void transaksi A harus melempar AppException
      expect(
        () async => await saleRepo.voidSale(
          saleId: saleA.sale.id,
          reason: 'Coba void transaksi yang ada retur',
          voidedByUserId: ownerUser.id,
        ),
        throwsA(isA<AppException>()),
      );

      // 5B. Transaksi yang sudah di-void tidak bisa diretur
      final saleB = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productB.id,
            productName: productB.name,
            qty: 2,
            price: productB.sellPrice,
            costPrice: productB.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 2 * productB.sellPrice),
        ],
      );

      await saleRepo.voidSale(
        saleId: saleB.sale.id,
        reason: 'Batalkan seluruh transaksi',
        voidedByUserId: ownerUser.id,
      );

      // Retur pada transaksi B harus melempar AppException
      expect(
        () async => await returnRepo.createReturn(
          CreateReturnInput(
            saleId: saleB.sale.id,
            deviceId: 'dev-01',
            createdBy: ownerUser.id,
            refundMethod: 'cash',
            reason: 'Coba retur transaksi yang sudah di-void',
            items: [
              CreateReturnItemInput(
                saleItemId: saleB.items.first.id,
                productId: productB.id,
                productName: productB.name,
                qty: 1,
                unitPrice: saleB.items.first.price,
                costPrice: saleB.items.first.costPrice,
                restock: true,
              ),
            ],
          ),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('6. Pajak proporsional terhitung benar & total refund tidak melebihi total transaksi', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Transaksi dengan pajak eksklusif 11%:
      // Subtotal 100k, Tax 11k, Total 111k (2 pcs @ 50k)
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 2,
            price: 50000,
            costPrice: 30000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'cash', amount: 111000),
        ],
        tax: 11000,
        taxRateBps: 1100,
        taxMode: 'exclusive',
      );

      expect(saleRes.sale.total, equals(111000));
      expect(saleRes.sale.tax, equals(11000));

      final saleItem = saleRes.items.first;

      // Retur 1 pcs (setengah subtotal: 50k)
      final ret1 = await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur item pertama berpajak',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productA.id,
              productName: productA.name,
              qty: 1,
              unitPrice: 50000,
              costPrice: 30000,
              restock: true,
            ),
          ],
        ),
      );

      // Pajak refund proporsional: 11000 * 50000 / 100000 = 5500
      expect(ret1.saleReturn.subtotal, equals(50000));
      expect(ret1.saleReturn.taxRefund, equals(5500));
      expect(ret1.saleReturn.total, equals(55500));

      // Retur 1 pcs sisanya
      final ret2 = await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur item kedua berpajak',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: productA.id,
              productName: productA.name,
              qty: 1,
              unitPrice: 50000,
              costPrice: 30000,
              restock: true,
            ),
          ],
        ),
      );

      expect(ret2.saleReturn.subtotal, equals(50000));
      expect(ret2.saleReturn.taxRefund, equals(5500));
      expect(ret2.saleReturn.total, equals(55500));

      // Total kumulatif pengembalian dana tepat sama dengan total awal transaksi (55500 + 55500 = 111000)
      final totalRefunded = ret1.saleReturn.total + ret2.saleReturn.total;
      expect(totalRefunded, equals(saleRes.sale.total));
    });

    test('7. Laporan: Omzet bersih, HPP bersih (hanya restock), laba kotor berkurang proporsional', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Transaksi: 2 pcs Item A (sell 50k, cost 30k) + 1 pc Item B (sell 100k, cost 60k)
      // Omzet = 200k, HPP = (2 * 30k) + (1 * 60k) = 120k, Laba kotor = 80k
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 2,
            price: 50000,
            costPrice: 30000,
          ),
          CheckoutCartItem(
            productId: productB.id,
            productName: productB.name,
            qty: 1,
            price: 100000,
            costPrice: 60000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'cash', amount: 200000),
        ],
      );

      final itemA = saleRes.items.firstWhere((i) => i.productId == productA.id);
      final itemB = saleRes.items.firstWhere((i) => i.productId == productB.id);

      // Retur 1 pc Item A dengan restock = true (HPP 30k kembali)
      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur item A restock',
          items: [
            CreateReturnItemInput(
              saleItemId: itemA.id,
              productId: productA.id,
              productName: productA.name,
              qty: 1,
              unitPrice: 50000,
              costPrice: 30000,
              restock: true,
            ),
          ],
        ),
      );

      // Retur 1 pc Item B dengan restock = false (HPP 60k TIDAK kembali karena barang rusak/beban)
      await returnRepo.createReturn(
        CreateReturnInput(
          saleId: saleRes.sale.id,
          deviceId: 'dev-01',
          createdBy: ownerUser.id,
          refundMethod: 'cash',
          reason: 'Retur item B non-restock',
          items: [
            CreateReturnItemInput(
              saleItemId: itemB.id,
              productId: productB.id,
              productName: productB.name,
              qty: 1,
              unitPrice: 100000,
              costPrice: 60000,
              restock: false,
            ),
          ],
        ),
      );

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

      final summary = await reportDao.getSummaryForRange(from: from, to: to);

      // Omzet Bruto: 200k
      expect(summary.grossOmzet, equals(200000));
      // Total Retur: 50k + 100k = 150k
      expect(summary.totalReturns, equals(150000));
      expect(summary.returnCount, equals(2));
      // Penjualan Bersih (Net Sales): 200k - 150k = 50k
      expect(summary.netSales, equals(50000));
      expect(summary.omzet, equals(50000));

      // HPP Bruto = 120k.
      expect(summary.grossCogs, equals(120000));
      // HPP Retur Restock (hanya Item A = 30k; Item B tidak di-restock sehingga tetap jadi beban).
      expect(summary.returnCogs, equals(30000));
      // HPP Bersih = 120k - 30k = 90k.
      expect(summary.cogs, equals(90000));

      // Pendapatan bersih = 50k (pajak 0).
      // Laba kotor = Net Revenue (50k) - Net COGS (90k) = -40k.
      expect(summary.grossProfit, equals(-40000));
    });

    test('8. User tanpa izin pos.return ditolak', () async {
      AuthService.to.currentUser.value = ownerUser;

      // Buat transaksi oleh owner
      final saleRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 2,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
          ),
        ],
        payments: [
          CheckoutPayment(method: 'cash', amount: 2 * productA.sellPrice),
        ],
      );

      // Ganti user aktif ke kasir tanpa izin pos.return
      AuthService.to.currentUser.value = staffUser;
      await permService.refreshPermissions();

      // Coba lakukan retur
      expect(
        () async => await returnRepo.createReturn(
          CreateReturnInput(
            saleId: saleRes.sale.id,
            deviceId: 'dev-01',
            createdBy: staffUser.id,
            refundMethod: 'cash',
            reason: 'Retur oleh staf',
            items: [
              CreateReturnItemInput(
                saleItemId: saleRes.items.first.id,
                productId: productA.id,
                productName: productA.name,
                qty: 1,
                unitPrice: productA.sellPrice,
                costPrice: productA.costPrice,
                restock: true,
              ),
            ],
          ),
        ),
        throwsA(
          isA<AppException>().having((e) => e.message, 'message', contains('pos.return')),
        ),
      );
    });
  });
}
