import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/audit_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/customer_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/sale_repository.dart';
import 'package:pos_me/app/data/repositories/sale_return_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockEntitlementProvider implements EntitlementProvider {
  Tier currentMockTier;
  MockEntitlementProvider(this.currentMockTier);

  @override
  Future<Tier> currentTier() async => currentMockTier;

  @override
  Stream<Tier> watchTier() => Stream.value(currentMockTier);
}

void main() {
  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late SettingsRepository settingsRepo;
  late StockRepository stockRepo;
  late ProductRepository productRepo;
  late SaleRepository saleRepo;
  late SaleReturnRepository returnRepo;
  late CustomerRepository customerRepo;
  late AuditRepository auditRepo;
  late PermissionService permService;
  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;

  late User ownerUser;
  late User cashierUser;
  late Product sampleProduct;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-customer-dev-001',
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
    auditRepo = AuditRepository(db.auditDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);
    Get.put<ProductRepository>(productRepo, permanent: true);
    Get.put<StockRepository>(stockRepo, permanent: true);
    Get.put<SaleRepository>(saleRepo, permanent: true);
    Get.put<SaleReturnRepository>(returnRepo, permanent: true);
    Get.put<AuditRepository>(auditRepo, permanent: true);
    Get.put<SettingsRepository>(settingsRepo, permanent: true);

    entitlementProvider = MockEntitlementProvider(Tier.semi);
    featureGate = FeatureGate(entitlementProvider);
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

    customerRepo = CustomerRepository(
      db,
      db.customerDao,
      featureGate: featureGate,
      permissionService: permService,
      auditService: auditService,
    );
    Get.put<CustomerRepository>(customerRepo, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    // Siapkan Toko & Pengguna Owner & Kasir
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Berkah Uji Kasbon'),
        mode: Value('team'),
        requireLogin: Value(false),
      ),
    );

    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Pemilik Toko'),
        roleId: Value(ownerRole!.id),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    final cashierRole = await roleRepo.getRoleByName('Kasir');
    final cashierId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('kasir'),
        displayName: const Value('Kasir Uji'),
        roleId: Value(cashierRole!.id),
      ),
    );
    cashierUser = (await userRepo.getUserById(cashierId))!;

    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();

    // Buat produk untuk transaksi
    final pId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Beras Premium 5kg'),
        sellPrice: Value(70000),
        costPrice: Value(50000),
        currentStock: Value(100),
        isActive: Value(true),
      ),
    );
    sampleProduct = (await productRepo.getProductById(pId))!;
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('Prompt 21: Pelanggan dan Kasbon Tests', () {
    test('1. Penjualan kasbon menambah saldo piutang pelanggan', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(
          name: 'Pak Budi',
          phone: '08123456789',
          creditLimit: 500000,
        ),
      );

      expect(customer.balance, 0);

      // Checkout dengan kasbon
      final result = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 2,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'credit', amount: 140000),
        ],
      );

      expect(result.sale.customerId, customer.id);

      // Cek saldo terkini
      final currentBalance = await customerRepo.getCustomerBalance(customer.id);
      expect(currentBalance, 140000);

      // Cek ledger
      final ledger = await customerRepo.getCustomerLedger(customer.id);
      expect(ledger.length, 1);
      expect(ledger.first.type, 'credit_sale');
      expect(ledger.first.debit, 140000);
      expect(ledger.first.credit, 0);
      expect(ledger.first.balanceAfter, 140000);
    });

    test('2. Pelunasan (terima pembayaran) mengurangi saldo piutang', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Bu Siti', creditLimit: 300000),
      );

      // Penjualan kasbon 140.000
      await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 2,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'credit', amount: 140000),
        ],
      );

      // Bayar cicilan kasbon 50.000
      await customerRepo.recordPayment(
        RecordCustomerPaymentInput(
          customerId: customer.id,
          amount: 50000,
          method: 'cash',
          note: 'Cicilan 1',
          deviceId: 'test-device',
        ),
      );

      final balanceAfterPay = await customerRepo.getCustomerBalance(customer.id);
      expect(balanceAfterPay, 90000);

      final ledger = await customerRepo.getCustomerLedger(customer.id);
      expect(ledger.length, 2);
      expect(ledger.first.type, 'payment');
      expect(ledger.first.credit, 50000);
      expect(ledger.first.balanceAfter, 90000);
    });

    test('3. Pelunasan melebihi saldo ditolak', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Pak Joko', creditLimit: 300000),
      );

      await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 1,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'credit', amount: 70000),
        ],
      );

      // Bayar 80.000 (melebihi saldo 70.000)
      expect(
        () => customerRepo.recordPayment(
          RecordCustomerPaymentInput(
            customerId: customer.id,
            amount: 80000,
            method: 'cash',
            deviceId: 'test-device',
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'EXCESSIVE_PAYMENT')),
      );

      final balance = await customerRepo.getCustomerBalance(customer.id);
      expect(balance, 70000);
    });

    test('4. Kasbon melebihi creditLimit ditolak', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Pak Agus', creditLimit: 100000),
      );

      // Belanja kasbon 140.000 (melebihi limit 100.000)
      expect(
        () => saleRepo.checkout(
          cashierId: ownerUser.id,
          deviceId: 'test-device',
          customerId: customer.id,
          items: [
            CheckoutCartItem(
              productId: sampleProduct.id,
              productName: sampleProduct.name,
              qty: 2,
              price: 70000,
              costPrice: 50000,
            ),
          ],
          payments: [
            const CheckoutPayment(method: 'credit', amount: 140000),
          ],
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'CREDIT_LIMIT_EXCEEDED')),
      );

      final balance = await customerRepo.getCustomerBalance(customer.id);
      expect(balance, 0);
    });

    test('5. Kasbon untuk pelanggan nonaktif ditolak', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Pak Doni', creditLimit: 200000),
      );

      await customerRepo.deactivateCustomer(customer.id);

      expect(
        () => saleRepo.checkout(
          cashierId: ownerUser.id,
          deviceId: 'test-device',
          customerId: customer.id,
          items: [
            CheckoutCartItem(
              productId: sampleProduct.id,
              productName: sampleProduct.name,
              qty: 1,
              price: 70000,
              costPrice: 50000,
            ),
          ],
          payments: [
            const CheckoutPayment(method: 'credit', amount: 70000),
          ],
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'CUSTOMER_INACTIVE')),
      );
    });

    test('6. Void penjualan kasbon otomatis membatalkan piutang (saldo berkurang kembali)', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Ibu Ani', creditLimit: 500000),
      );

      final checkoutRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 1,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'credit', amount: 70000),
        ],
      );

      expect(await customerRepo.getCustomerBalance(customer.id), 70000);

      // Void transaksi penjualan kasbon
      await saleRepo.voidSale(
        saleId: checkoutRes.sale.id,
        reason: 'Salah pencatatan kasbon pelanggan',
      );

      // Karena penjualan berstatus void, saldo kasbon otomatis kembali 0
      final balanceAfterVoid = await customerRepo.getCustomerBalance(customer.id);
      expect(balanceAfterVoid, 0);
    });

    test('7. Retur penjualan kasbon memotong saldo piutang dulu, sisanya baru tunai', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Pak Hendra', creditLimit: 500000),
      );

      final checkoutRes = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 2,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'credit', amount: 140000),
        ],
      );

      expect(await customerRepo.getCustomerBalance(customer.id), 140000);

      final saleItem = checkoutRes.items.first;

      // Retur 1 barang (nominal retur 70.000)
      final returnResult = await returnRepo.createReturn(
        CreateReturnInput(
          saleId: checkoutRes.sale.id,
          deviceId: 'test-device',
          items: [
            CreateReturnItemInput(
              saleItemId: saleItem.id,
              productId: sampleProduct.id,
              productName: sampleProduct.name,
              qty: 1,
              unitPrice: 70000,
              costPrice: 50000,
              restock: true,
            ),
          ],
          refundMethod: 'cash',
          reason: 'Barang rusak',
          createdBy: ownerUser.id,
        ),
      );

      // Karena pembelian memakai kasbon 140.000, retur 70.000 otomatis memotong kasbon
      expect(returnResult.saleReturn.creditRefund, 70000);

      final balanceAfterReturn = await customerRepo.getCustomerBalance(customer.id);
      expect(balanceAfterReturn, 70000);

      final ledger = await customerRepo.getCustomerLedger(customer.id);
      expect(ledger.length, 2);
      expect(ledger.first.type, 'credit_return');
      expect(ledger.first.credit, 70000);
      expect(ledger.first.balanceAfter, 70000);
    });

    test('8. Split payment tunai + kasbon tercatat proporsional dan saldo bertambah sebesar porsi kasbon', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final customer = await customerRepo.createCustomer(
        const CreateCustomerInput(name: 'Pak Bambang', creditLimit: 500000),
      );

      // Total transaksi 140.000: Tunai 40.000, Kasbon 100.000
      final result = await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: customer.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 2,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'cash', amount: 40000),
          const CheckoutPayment(method: 'credit', amount: 100000),
        ],
      );

      expect(result.payments.length, 2);

      // Saldo bertambah hanya sebesar porsi kasbon (100.000)
      final balance = await customerRepo.getCustomerBalance(customer.id);
      expect(balance, 100000);
    });

    test('9. Pelanggan di tier Gratis atau role kasir tanpa izin manage/collect ditolak di level Repository', () async {
      // 9a. Test Tier Gratis ditolak
      entitlementProvider.currentMockTier = Tier.free;
      await featureGate.init();

      expect(
        () => customerRepo.getCustomers(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );

      expect(
        () => customerRepo.createCustomer(const CreateCustomerInput(name: 'Uji Tier')),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED')),
      );

      // Kembalikan ke Tier Semi
      entitlementProvider.currentMockTier = Tier.semi;
      await featureGate.init();

      // 9b. Role Kasir: Punya customer.view, tapi tidak punya customer.manage atau customer.collect
      AuthService.to.currentUser.value = cashierUser;
      await permService.refreshPermissions();

      // Kasir bisa melihat pelanggan
      final list = await customerRepo.getCustomers();
      expect(list, isNotNull);

      // Kasir TIDAK bisa menambah pelanggan
      expect(
        () => customerRepo.createCustomer(const CreateCustomerInput(name: 'Pelanggan Kasir')),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );

      // Kasir TIDAK bisa menerima pelunasan hutang
      expect(
        () => customerRepo.recordPayment(
          const RecordCustomerPaymentInput(
            customerId: 1,
            amount: 10000,
            deviceId: 'test-device',
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('10. Backup & restore mempertahankan konsistensi saldo piutang (dihitung ulang dari data yang direstore menghasilkan angka identik)', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      final c1 = await customerRepo.createCustomer(const CreateCustomerInput(name: 'Pelanggan A'));
      final c2 = await customerRepo.createCustomer(const CreateCustomerInput(name: 'Pelanggan B'));

      // c1 kasbon 70.000
      await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: c1.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 1,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [const CheckoutPayment(method: 'credit', amount: 70000)],
      );

      // c2 kasbon 140.000, bayar 40.000 -> sisa 100.000
      await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'test-device',
        customerId: c2.id,
        items: [
          CheckoutCartItem(
            productId: sampleProduct.id,
            productName: sampleProduct.name,
            qty: 2,
            price: 70000,
            costPrice: 50000,
          ),
        ],
        payments: [const CheckoutPayment(method: 'credit', amount: 140000)],
      );

      await customerRepo.recordPayment(
        RecordCustomerPaymentInput(
          customerId: c2.id,
          amount: 40000,
          deviceId: 'test-device',
        ),
      );

      final originalBalanceC1 = await customerRepo.getCustomerBalance(c1.id);
      final originalBalanceC2 = await customerRepo.getCustomerBalance(c2.id);
      final originalTotalReceivables = await customerRepo.getTotalReceivables();

      expect(originalBalanceC1, 70000);
      expect(originalBalanceC2, 100000);
      expect(originalTotalReceivables, 170000);

      // Simulasi database baru (seperti setelah restore)
      final restoredDb = AppDatabase(NativeDatabase.memory());
      final allCust = await db.select(db.customers).get();
      for (final row in allCust) {
        await restoredDb.into(restoredDb.customers).insert(row);
      }
      final allSales = await db.select(db.sales).get();
      for (final row in allSales) {
        await restoredDb.into(restoredDb.sales).insert(row);
      }
      final allPayments = await db.select(db.payments).get();
      for (final row in allPayments) {
        await restoredDb.into(restoredDb.payments).insert(row);
      }
      final allCustPayments = await db.select(db.customerPayments).get();
      for (final row in allCustPayments) {
        await restoredDb.into(restoredDb.customerPayments).insert(row);
      }

      // Hitung ulang saldo pada database yang di-restore
      final restoredBalanceC1 = await restoredDb.customerDao.getCustomerBalance(c1.id);
      final restoredBalanceC2 = await restoredDb.customerDao.getCustomerBalance(c2.id);
      final restoredTotalReceivables = await restoredDb.customerDao.getTotalReceivables();

      expect(restoredBalanceC1, originalBalanceC1);
      expect(restoredBalanceC2, originalBalanceC2);
      expect(restoredTotalReceivables, originalTotalReceivables);

      await restoredDb.close();
    });
  });
}
