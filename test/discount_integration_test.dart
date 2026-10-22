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
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/license_repository.dart';
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

void main() {
  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late ProductRepository productRepo;
  late StockRepository stockRepo;
  late SaleRepository saleRepo;
  late SaleReturnRepository returnRepo;
  late LicenseRepository licenseRepo;
  late SettingsRepository settingsRepo;
  late AuditRepository auditRepo;
  late PermissionService permService;

  late User ownerUser;
  late User staffUserNoDiscount;
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
      'app_device_id': 'test-discount-dev-001',
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
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao, stockRepo);
    returnRepo = SaleReturnRepository(
      db,
      db.saleReturnDao,
      db.saleDao,
      stockRepo,
    );
    licenseRepo = LicenseRepository(db.licenseDao);
    auditRepo = AuditRepository(db.auditDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);
    Get.put<ProductRepository>(productRepo, permanent: true);
    Get.put<StockRepository>(stockRepo, permanent: true);
    Get.put<SaleRepository>(saleRepo, permanent: true);
    Get.put<SaleReturnRepository>(returnRepo, permanent: true);
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

    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Diskon Test'),
        mode: Value('team'),
        requireLogin: Value(true),
      ),
    );
    final store = (await storeRepo.getStore())!;
    authService.currentStore.value = store;

    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Pemilik Toko'),
        roleId: Value(ownerRole!.id),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    // Kasir magang tanpa izin pos.discount
    final internRoleId = await roleRepo.insertRole(
      const RolesCompanion(
        name: Value('KasirMagang'),
        description: Value('Kasir Percobaan Tanpa Diskon'),
        isLocked: Value(false),
      ),
    );
    await roleRepo.addPermission(
      RolePermissionsCompanion(
        roleId: Value(internRoleId),
        permissionKey: const Value('pos.sell'),
      ),
    );
    final staffId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('kasir_nodisc'),
        displayName: const Value('Kasir No Disc'),
        roleId: Value(internRoleId),
      ),
    );
    staffUserNoDiscount = (await userRepo.getUserById(staffId))!;

    final pAId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Kopi Susu'),
        sellPrice: Value(20000),
        costPrice: Value(12000),
        currentStock: Value(50),
        isActive: Value(true),
      ),
    );
    productA = (await productRepo.getProductById(pAId))!;

    final pBId = await productRepo.createProduct(
      const ProductsCompanion(
        name: Value('Roti Bakar'),
        sellPrice: Value(30000),
        costPrice: Value(18000),
        currentStock: Value(50),
        isActive: Value(true),
      ),
    );
    productB = (await productRepo.getProductById(pBId))!;
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  test('Checkout with item discount and overall discount stores shares correctly', () async {
    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();

    // 2 x Kopi (20,000) with disc 2,000/unit -> subtotal = (20000 - 2000) * 2 = 36,000
    // 1 x Roti (30,000) with disc 0 -> subtotal = 30,000
    // Gross Subtotal = 70,000; Items Discount = 4,000; Subtotal = 66,000
    // Overall discount = 6,000 -> Total discount = 10,000 -> Net basis = 60,000
    final result = await saleRepo.checkout(
      cashierId: ownerUser.id,
      deviceId: 'dev-01',
      items: [
        CheckoutCartItem(
          productId: productA.id,
          productName: productA.name,
          qty: 2,
          price: productA.sellPrice,
          costPrice: productA.costPrice,
          discount: 2000,
        ),
        CheckoutCartItem(
          productId: productB.id,
          productName: productB.name,
          qty: 1,
          price: productB.sellPrice,
          costPrice: productB.costPrice,
          discount: 0,
        ),
      ],
      payments: const [CheckoutPayment(method: 'cash', amount: 60000)],
      overallDiscount: 6000,
    );

    expect(result.sale.subtotal, equals(70000));
    expect(result.sale.discount, equals(10000)); // 4000 item + 6000 overall
    expect(result.sale.total, equals(60000));

    expect(result.items.length, equals(2));
    final itemA = result.items.firstWhere((i) => i.productId == productA.id);
    final itemB = result.items.firstWhere((i) => i.productId == productB.id);

    expect(itemA.discount, equals(2000));
    expect(itemA.subtotal, equals(36000));
    expect(itemB.discount, equals(0));
    expect(itemB.subtotal, equals(30000));

    // Sum of discountShare must equal exactly 6000
    expect(itemA.discountShare + itemB.discountShare, equals(6000));
    // Item A subtotal 36k vs Item B subtotal 30k -> total 66k
    // 6000 * 36 / 66 = 3272.72 -> 3273
    // 6000 * 30 / 66 = 2727.27 -> 2727
    expect(itemA.discountShare, equals(3273));
    expect(itemB.discountShare, equals(2727));
  });

  test('Dual-layer permission: user without pos.discount is rejected by repository', () async {
    AuthService.to.currentUser.value = staffUserNoDiscount;
    await permService.refreshPermissions();

    // Attempt item discount
    expect(
      () => saleRepo.checkout(
        cashierId: staffUserNoDiscount.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 1,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
            discount: 5000,
          ),
        ],
        payments: const [CheckoutPayment(method: 'cash', amount: 15000)],
      ),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN_DISCOUNT')),
    );

    // Attempt overall discount
    expect(
      () => saleRepo.checkout(
        cashierId: staffUserNoDiscount.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: productA.id,
            productName: productA.name,
            qty: 1,
            price: productA.sellPrice,
            costPrice: productA.costPrice,
            discount: 0,
          ),
        ],
        payments: const [CheckoutPayment(method: 'cash', amount: 15000)],
        overallDiscount: 5000,
      ),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'FORBIDDEN_DISCOUNT')),
    );
  });

  test('Discount combined with Exclusive tax calculates tax on net basis', () async {
    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();

    // Product B: 1 x 30,000. Overall discount 10,000 -> Net basis = 20,000.
    // Tax: exclusive 11% (1100 bps) of 20,000 = 2,200.
    // Total = 22,200.
    final result = await saleRepo.checkout(
      cashierId: ownerUser.id,
      deviceId: 'dev-01',
      items: [
        CheckoutCartItem(
          productId: productB.id,
          productName: productB.name,
          qty: 1,
          price: productB.sellPrice,
          costPrice: productB.costPrice,
        ),
      ],
      payments: const [CheckoutPayment(method: 'cash', amount: 22200)],
      overallDiscount: 10000,
      taxRateBps: 1100,
      taxMode: 'exclusive',
    );

    expect(result.sale.subtotal, equals(30000));
    expect(result.sale.discount, equals(10000));
    expect(result.sale.tax, equals(2200));
    expect(result.sale.total, equals(22200));
  });

  test('Return on sale with discount calculates proportional refund based on net paid', () async {
    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();

    // Buy 2 x Kopi (20k each) with item discount 5k each. Subtotal = (20k - 5k) * 2 = 30k.
    // Plus overall discount 4k. Net paid = 26k.
    // Item discountShare = 4k.
    // Net for 2 units = 30k - 4k = 26k. Effective unit price = 13k.
    final checkoutRes = await saleRepo.checkout(
      cashierId: ownerUser.id,
      deviceId: 'dev-01',
      items: [
        CheckoutCartItem(
          productId: productA.id,
          productName: productA.name,
          qty: 2,
          price: productA.sellPrice,
          costPrice: productA.costPrice,
          discount: 5000,
        ),
      ],
      payments: const [CheckoutPayment(method: 'cash', amount: 26000)],
      overallDiscount: 4000,
    );

    final saleItem = checkoutRes.items.first;
    expect(saleItem.discountShare, equals(4000));
    expect(saleItem.subtotal, equals(30000));

    // Return 1 unit of Kopi
    final ret = await returnRepo.createReturn(
      CreateReturnInput(
        saleId: checkoutRes.sale.id,
        deviceId: 'dev-01',
        items: [
          CreateReturnItemInput(
            saleItemId: saleItem.id,
            productId: productA.id,
            productName: productA.name,
            qty: 1,
            unitPrice: (saleItem.subtotal - saleItem.discountShare) ~/ saleItem.qty,
            costPrice: saleItem.costPrice,
            restock: true,
          ),
        ],
        refundMethod: 'cash',
        reason: 'Barang tidak cocok',
      ),
    );

    // Refund must be 13,000 (net unit price after item discount and discount share)
    expect(ret.saleReturn.total, equals(13000));
    expect(ret.items.first.subtotal, equals(13000));
  });
}
