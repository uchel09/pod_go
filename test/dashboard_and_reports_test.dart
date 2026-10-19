import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/features/entitlement_provider.dart';
import 'package:pos_me/app/core/features/tier_enum.dart';
import 'package:pos_me/app/core/permissions/permission_keys.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/feature_gate.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/local/daos/role_dao.dart';
import 'package:pos_me/app/data/local/daos/sale_dao.dart';
import 'package:pos_me/app/data/local/daos/store_dao.dart';
import 'package:pos_me/app/data/local/daos/user_dao.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
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
  late SaleDao saleDao;
  late ReportDao reportDao;
  late RoleDao roleDao;
  late StoreDao storeDao;
  late UserDao userDao;

  late ReportRepository reportRepo;
  late RoleRepository roleRepo;
  late StoreRepository storeRepo;
  late UserRepository userRepo;

  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;
  late PermissionService permissionService;

  late int ownerRoleId;
  late int cashierRoleId;
  late User ownerUser;
  late User cashierUser;

  setUp(() async {
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    productDao = db.productDao;
    saleDao = db.saleDao;
    reportDao = ReportDao(db);
    roleDao = db.roleDao;
    storeDao = db.storeDao;
    userDao = db.userDao;

    storeRepo = StoreRepository(storeDao);
    userRepo = UserRepository(userDao);
    roleRepo = RoleRepository(roleDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);

    entitlementProvider = MockEntitlementProvider(Tier.free);
    featureGate = FeatureGate(entitlementProvider);
    Get.put<FeatureGate>(featureGate, permanent: true);

    permissionService = PermissionService(roleRepo);
    Get.put<PermissionService>(permissionService, permanent: true);

    reportRepo = ReportRepository(
      reportDao,
      permissionService: permissionService,
      featureGate: featureGate,
    );
    Get.put<ReportRepository>(reportRepo, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);
    final roles = await roleRepo.getAllRoles();
    ownerRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'owner').id;
    cashierRoleId = roles.firstWhere((r) => r.name.toLowerCase() == 'kasir').id;

    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko Sukses Makmur'),
        mode: drift.Value('solo'),
        requireLogin: drift.Value(false),
      ),
    );

    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('owner'),
        displayName: const drift.Value('Pemilik Toko'),
        roleId: drift.Value(ownerRoleId),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    final cashierId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('kasir1'),
        displayName: const drift.Value('Kasir 1'),
        roleId: drift.Value(cashierRoleId),
      ),
    );
    cashierUser = (await userRepo.getUserById(cashierId))!;

    final authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  Future<int> createTestProduct({
    required String name,
    required int costPrice,
    required int sellPrice,
    int currentStock = 100,
    int minStock = 5,
    int? categoryId,
  }) {
    return productDao.insertProduct(
      ProductsCompanion(
        name: drift.Value(name),
        costPrice: drift.Value(costPrice),
        sellPrice: drift.Value(sellPrice),
        currentStock: drift.Value(currentStock),
        minStock: drift.Value(minStock),
        categoryId: drift.Value(categoryId),
        isActive: const drift.Value(true),
      ),
    );
  }

  Future<int> insertSaleRecord({
    required String invoiceNo,
    required int total,
    required int cashierId,
    required DateTime createdAt,
    String status = 'completed',
    int tax = 0,
    List<({int productId, String name, int qty, int price, int costPrice})> items = const [],
    List<({String method, int amount})> payments = const [],
  }) async {
    final saleId = await saleDao.insertSale(
      SalesCompanion(
        uuid: drift.Value('uuid-$invoiceNo'),
        deviceId: const drift.Value('device-test'),
        invoiceNo: drift.Value(invoiceNo),
        cashierId: drift.Value(cashierId),
        subtotal: drift.Value(total - tax),
        tax: drift.Value(tax),
        total: drift.Value(total),
        paid: drift.Value(total),
        change: const drift.Value(0),
        status: drift.Value(status),
        createdAt: drift.Value(createdAt),
        updatedAt: drift.Value(createdAt),
      ),
    );

    for (final item in items) {
      await saleDao.insertSaleItem(
        SaleItemsCompanion(
          saleId: drift.Value(saleId),
          productId: drift.Value(item.productId),
          productName: drift.Value(item.name),
          qty: drift.Value(item.qty),
          price: drift.Value(item.price),
          costPrice: drift.Value(item.costPrice),
          subtotal: drift.Value(item.qty * item.price),
          createdAt: drift.Value(createdAt),
          updatedAt: drift.Value(createdAt),
        ),
      );
    }

    for (final p in payments) {
      await saleDao.insertPayment(
        PaymentsCompanion(
          saleId: drift.Value(saleId),
          method: drift.Value(p.method),
          amount: drift.Value(p.amount),
          createdAt: drift.Value(createdAt),
          updatedAt: drift.Value(createdAt),
        ),
      );
    }

    return saleId;
  }

  test('1. Omzet mengabaikan transaksi berstatus void', () async {
    final now = DateTime.now();
    final pId = await createTestProduct(
      name: 'Kopi Susu',
      costPrice: 8000,
      sellPrice: 15000,
    );

    // Transaksi 1: Completed (Rp 30.000)
    await insertSaleRecord(
      invoiceNo: 'INV-001',
      total: 30000,
      cashierId: ownerUser.id,
      createdAt: now,
      status: 'completed',
      items: [
        (
          productId: pId,
          name: 'Kopi Susu',
          qty: 2,
          price: 15000,
          costPrice: 8000,
        ),
      ],
    );

    // Transaksi 2: Void (Rp 45.000)
    await insertSaleRecord(
      invoiceNo: 'INV-002',
      total: 45000,
      cashierId: ownerUser.id,
      createdAt: now,
      status: 'void',
      items: [
        (
          productId: pId,
          name: 'Kopi Susu',
          qty: 3,
          price: 15000,
          costPrice: 8000,
        ),
      ],
    );

    final dashboard = await reportRepo.getDashboardData();

    expect(dashboard.todayOmzet, equals(30000));
    expect(dashboard.todayTxCount, equals(1));
    expect(dashboard.todayItemsSold, equals(2));
  });

  test('2. HPP dan laba kotor benar untuk 2 transaksi terpisah', () async {
    final now = DateTime.now();
    final p1 = await createTestProduct(
      name: 'Snack A',
      costPrice: 5000,
      sellPrice: 8000,
    );
    final p2 = await createTestProduct(
      name: 'Minuman B',
      costPrice: 10000,
      sellPrice: 15000,
    );

    // Transaksi 1: 2 x Snack A (Omzet: 16.000, HPP: 10.000)
    await insertSaleRecord(
      invoiceNo: 'INV-A',
      total: 16000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (productId: p1, name: 'Snack A', qty: 2, price: 8000, costPrice: 5000),
      ],
    );

    // Transaksi 2: 1 x Minuman B + 1 x Snack A (Omzet: 23.000, HPP: 15.000)
    await insertSaleRecord(
      invoiceNo: 'INV-B',
      total: 23000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (
          productId: p2,
          name: 'Minuman B',
          qty: 1,
          price: 15000,
          costPrice: 10000,
        ),
        (productId: p1, name: 'Snack A', qty: 1, price: 8000, costPrice: 5000),
      ],
    );

    // Set active user as Owner (has report.view_profit)
    AuthService.to.currentUser.value = ownerUser;
    final dashboard = await reportRepo.getDashboardData();

    expect(dashboard.todayOmzet, equals(39000)); // 16.000 + 23.000
    expect(dashboard.todayTxCount, equals(2));
    expect(dashboard.todayItemsSold, equals(4)); // 2 + 1 + 1
    expect(dashboard.todayCogs, equals(25000)); // 10.000 + 15.000
    expect(dashboard.todayProfit, equals(14000)); // 39.000 - 25.000
  });

  test('3. Batas hari lokal benar di sekitar tengah malam', () async {
    // Patokan "hari ini" adalah 2026-10-19 waktu lokal
    final customToday = DateTime(2026, 10, 19, 14, 30, 0);

    final pId = await createTestProduct(
      name: 'Item Mid',
      costPrice: 1000,
      sellPrice: 2000,
    );

    // Kemarin malam 23:59:00 (harus TIDAK masuk hitungan hari ini)
    await insertSaleRecord(
      invoiceNo: 'INV-YESTERDAY',
      total: 10000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 18, 23, 59, 0),
      items: [
        (
          productId: pId,
          name: 'Item Mid',
          qty: 5,
          price: 2000,
          costPrice: 1000,
        ),
      ],
    );

    // Tepat setelah tengah malam 00:01:00 (harus MASUK)
    await insertSaleRecord(
      invoiceNo: 'INV-MIDNIGHT-START',
      total: 20000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 19, 0, 1, 0),
      items: [
        (
          productId: pId,
          name: 'Item Mid',
          qty: 10,
          price: 2000,
          costPrice: 1000,
        ),
      ],
    );

    // Menjelang tengah malam 23:59:30 (harus MASUK)
    await insertSaleRecord(
      invoiceNo: 'INV-MIDNIGHT-END',
      total: 30000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 19, 23, 59, 30),
      items: [
        (
          productId: pId,
          name: 'Item Mid',
          qty: 15,
          price: 2000,
          costPrice: 1000,
        ),
      ],
    );

    // Besok pagi 00:05:00 (harus TIDAK masuk hitungan hari ini)
    await insertSaleRecord(
      invoiceNo: 'INV-TOMORROW',
      total: 40000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 20, 0, 5, 0),
      items: [
        (
          productId: pId,
          name: 'Item Mid',
          qty: 20,
          price: 2000,
          costPrice: 1000,
        ),
      ],
    );

    final dashboard = await reportRepo.getDashboardData(customNow: customToday);

    // Hanya INV-MIDNIGHT-START (20.000) dan INV-MIDNIGHT-END (30.000)
    expect(dashboard.todayOmzet, equals(50000));
    expect(dashboard.todayTxCount, equals(2));
    expect(dashboard.todayItemsSold, equals(25));
  });

  test(
    '4. Role Kasir tanpa report.view_profit TIDAK mendapat angka laba/HPP dari repository',
    () async {
      final now = DateTime.now();
      final pId = await createTestProduct(
        name: 'Barang Rahasia',
        costPrice: 4000,
        sellPrice: 10000,
      );

      await insertSaleRecord(
        invoiceNo: 'INV-KASIR',
        total: 10000,
        cashierId: cashierUser.id,
        createdAt: now,
        items: [
          (
            productId: pId,
            name: 'Barang Rahasia',
            qty: 1,
            price: 10000,
            costPrice: 4000,
          ),
        ],
      );

      // Ubah ke multi_user dan aktifkan sesi pengguna kasir
      await storeDao.updateStore(
        const StoresCompanion(
          id: drift.Value(1),
          name: drift.Value('Toko Sukses Makmur'),
          mode: drift.Value('multi_user'),
          requireLogin: drift.Value(true),
        ),
      );
      AuthService.to.currentUser.value = cashierUser;
      await AuthService.to.refreshState();
      await permissionService.refreshPermissions();

      // Pastikan Kasir tidak punya izin report.view_profit
      expect(permissionService.can(PermissionKeys.reportViewProfit), isFalse);

      final dashboard = await reportRepo.getDashboardData();

      // Omzet dan transaksi tetap bisa dilihat
      expect(dashboard.todayOmzet, equals(10000));
      expect(dashboard.todayTxCount, equals(1));
      expect(dashboard.todayItemsSold, equals(1));

      // Angka sensitif laba dan HPP wajib bernilai NULL
      expect(dashboard.todayProfit, isNull);
      expect(dashboard.todayCogs, isNull);
    },
  );

  test(
    '5. Role Owner dengan report.view_profit mendapat angka laba dan HPP lengkap',
    () async {
      final now = DateTime.now();
      final pId = await createTestProduct(
        name: 'Barang Owner',
        costPrice: 6000,
        sellPrice: 10000,
      );

      await insertSaleRecord(
        invoiceNo: 'INV-OWNER',
        total: 20000,
        cashierId: ownerUser.id,
        createdAt: now,
        items: [
          (
            productId: pId,
            name: 'Barang Owner',
            qty: 2,
            price: 10000,
            costPrice: 6000,
          ),
        ],
      );

      // Aktifkan sesi pengguna owner
      AuthService.to.currentUser.value = ownerUser;
      await AuthService.to.refreshState();
      await permissionService.refreshPermissions();
      expect(permissionService.can(PermissionKeys.reportViewProfit), isTrue);

      final dashboard = await reportRepo.getDashboardData();

      expect(dashboard.todayOmzet, equals(20000));
      expect(dashboard.todayCogs, equals(12000));
      expect(dashboard.todayProfit, equals(8000));
    },
  );

  test('6. getDailySalesReport memvalidasi izin report.view_basic', () async {
    final now = DateTime.now();
    final pId = await createTestProduct(
      name: 'Produk Laporan',
      costPrice: 2000,
      sellPrice: 5000,
    );

    await insertSaleRecord(
      invoiceNo: 'INV-LAPORAN',
      total: 15000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (
          productId: pId,
          name: 'Produk Laporan',
          qty: 3,
          price: 5000,
          costPrice: 2000,
        ),
      ],
    );

    // Owner memiliki report.view_basic
    AuthService.to.currentUser.value = ownerUser;
    final reports = await reportRepo.getDailySalesReport();
    expect(reports.isNotEmpty, isTrue);
    expect(reports.first.omzet, equals(15000));
    expect(reports.first.txCount, equals(1));

    // Ubah ke mode multi-user dengan user role Tamu tanpa izin report.view_basic
    await storeDao.updateStore(
      const StoresCompanion(
        id: drift.Value(1),
        name: drift.Value('Toko Sukses Makmur'),
        mode: drift.Value('multi_user'),
        requireLogin: drift.Value(true),
      ),
    );
    final noPermRoleId = await roleRepo.insertRole(
      const RolesCompanion(name: drift.Value('Tamu')),
    );
    final noPermUserId = await userRepo.insertUser(
      UsersCompanion(
        username: const drift.Value('tamu'),
        displayName: const drift.Value('Tamu'),
        roleId: drift.Value(noPermRoleId),
      ),
    );
    final tamuUser = (await userRepo.getUserById(noPermUserId))!;
    AuthService.to.currentUser.value = tamuUser;
    await AuthService.to.refreshState();
    await permissionService.refreshPermissions();

    expect(permissionService.can(PermissionKeys.reportViewBasic), isFalse);

    expect(
      () => reportRepo.getDailySalesReport(),
      throwsA(isA<AppException>()),
    );
  });

  test(
    '7. Grafik omzet 7 hari terakhir mengembalikan tepat 7 data point berurutan',
    () async {
      final now = DateTime(2026, 10, 19, 12, 0, 0);
      final pId = await createTestProduct(
        name: 'Barang Grafik',
        costPrice: 500,
        sellPrice: 1000,
      );

      // Transaksi di hari ini dan 2 hari lalu
      await insertSaleRecord(
        invoiceNo: 'INV-TODAY',
        total: 5000,
        cashierId: ownerUser.id,
        createdAt: DateTime(2026, 10, 19, 10, 0, 0),
        items: [
          (
            productId: pId,
            name: 'Barang Grafik',
            qty: 5,
            price: 1000,
            costPrice: 500,
          ),
        ],
      );

      await insertSaleRecord(
        invoiceNo: 'INV-2DAYS-AGO',
        total: 7000,
        cashierId: ownerUser.id,
        createdAt: DateTime(2026, 10, 17, 10, 0, 0),
        items: [
          (
            productId: pId,
            name: 'Barang Grafik',
            qty: 7,
            price: 1000,
            costPrice: 500,
          ),
        ],
      );

      final dashboard = await reportRepo.getDashboardData(customNow: now);
      final chart = dashboard.revenueChart;

      expect(chart.length, equals(7));
      expect(chart.first.dateStr, equals('2026-10-13'));
      expect(chart.last.dateStr, equals('2026-10-19'));

      // Hari tanpa transaksi tetap memiliki omzet 0
      final emptyDay = chart.firstWhere((p) => p.dateStr == '2026-10-14');
      expect(emptyDay.omzet, equals(0));
      expect(emptyDay.txCount, equals(0));

      // Hari dengan transaksi terisi akurat
      final day17 = chart.firstWhere((p) => p.dateStr == '2026-10-17');
      expect(day17.omzet, equals(7000));
      expect(day17.txCount, equals(1));

      final day19 = chart.firstWhere((p) => p.dateStr == '2026-10-19');
      expect(day19.omzet, equals(5000));
      expect(day19.txCount, equals(1));
    },
  );

  test(
    '8. Filter produk stok menipis (currentStock <= minStock) maksimal 5 item',
    () async {
      // 6 produk stok menipis
      for (int i = 1; i <= 6; i++) {
        await createTestProduct(
          name: 'Produk Menipis $i',
          costPrice: 1000,
          sellPrice: 2000,
          currentStock: i,
          minStock: 10,
        );
      }
      // 1 produk stok aman
      await createTestProduct(
        name: 'Produk Aman',
        costPrice: 1000,
        sellPrice: 2000,
        currentStock: 50,
        minStock: 10,
      );

      final dashboard = await reportRepo.getDashboardData();

      expect(dashboard.totalLowStockCount, equals(6));
      expect(dashboard.lowStockProducts.length, equals(5)); // limit 5
      expect(
        dashboard.lowStockProducts.any((p) => p.name == 'Produk Aman'),
        isFalse,
      );
      // Terurut berdasarkan currentStock terendah
      expect(dashboard.lowStockProducts.first.currentStock, equals(1));
    },
  );

  test('9. Tier Gratis DITOLAK saat memanggil getFullReport (code: FEATURE_LOCKED)', () async {
    featureGate.tier.value = Tier.free;
    final now = DateTime.now();

    expect(
      () => reportRepo.getFullReport(
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day + 1),
      ),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'FEATURE_LOCKED'),
      ),
    );
  });

  test('10. Tier Semi-Premium BERHASIL memanggil getFullReport, menampilkan ringkasan, produk terlaris, kategori, dan metode pembayaran', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    // Kategori
    final catMakananId = await db.categoryDao.insertCategory(
      const CategoriesCompanion(name: drift.Value('Makanan')),
    );
    final catMinumanId = await db.categoryDao.insertCategory(
      const CategoriesCompanion(name: drift.Value('Minuman')),
    );

    // Produk
    final p1 = await createTestProduct(
      name: 'Nasi Goreng',
      costPrice: 10000,
      sellPrice: 15000,
      categoryId: catMakananId,
    );
    final p2 = await createTestProduct(
      name: 'Es Teh Manis',
      costPrice: 2000,
      sellPrice: 5000,
      categoryId: catMinumanId,
    );

    // Transaksi 1: Cash Rp 30.000 (2 x Nasi Goreng)
    await insertSaleRecord(
      invoiceNo: 'INV-FULL-1',
      total: 30000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (productId: p1, name: 'Nasi Goreng', qty: 2, price: 15000, costPrice: 10000),
      ],
      payments: [(method: 'cash', amount: 30000)],
    );

    // Transaksi 2: QRIS Rp 30.000 (1 x Nasi Goreng + 3 x Es Teh Manis)
    await insertSaleRecord(
      invoiceNo: 'INV-FULL-2',
      total: 30000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (productId: p1, name: 'Nasi Goreng', qty: 1, price: 15000, costPrice: 10000),
        (productId: p2, name: 'Es Teh Manis', qty: 3, price: 5000, costPrice: 2000),
      ],
      payments: [(method: 'qris', amount: 30000)],
    );

    AuthService.to.currentUser.value = ownerUser;
    final fullReport = await reportRepo.getFullReport(from: todayStart, to: todayEnd);

    // Ringkasan
    expect(fullReport.summary.omzet, equals(60000));
    expect(fullReport.summary.txCount, equals(2));
    expect(fullReport.summary.itemsSold, equals(6)); // 2 + 1 + 3
    expect(fullReport.avgTxValue, equals(30000));

    // Produk Terlaris (default sortBy = 'qty')
    expect(fullReport.topProducts.length, equals(2));
    expect(fullReport.topProducts.first.productName, equals('Nasi Goreng'));
    expect(fullReport.topProducts.first.totalQty, equals(3));
    expect(fullReport.topProducts.first.totalRevenue, equals(45000));
    expect(fullReport.topProducts[1].productName, equals('Es Teh Manis'));
    expect(fullReport.topProducts[1].totalQty, equals(3));

    // Kategori
    expect(fullReport.categorySales.length, equals(2));
    final catMakanan = fullReport.categorySales.firstWhere((c) => c.categoryName == 'Makanan');
    expect(catMakanan.totalRevenue, equals(45000));
    expect(catMakanan.percentage, equals(75.0)); // 45.000 / 60.000 = 75%

    final catMinuman = fullReport.categorySales.firstWhere((c) => c.categoryName == 'Minuman');
    expect(catMinuman.totalRevenue, equals(15000));
    expect(catMinuman.percentage, equals(25.0)); // 15.000 / 60.000 = 25%

    // Metode Pembayaran
    expect(fullReport.paymentMethodSales.length, equals(2));
    final payCash = fullReport.paymentMethodSales.firstWhere((p) => p.method == 'cash');
    expect(payCash.totalAmount, equals(30000));
    expect(payCash.percentage, equals(50.0));

    final payQris = fullReport.paymentMethodSales.firstWhere((p) => p.method == 'qris');
    expect(payQris.totalAmount, equals(30000));
    expect(payQris.percentage, equals(50.0));
  });

  test('11. Pengurutan produk terlaris berdasarkan Omzet (revenue)', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    // Produk Murah: Qty 10 @ Rp 2.000 = Omzet Rp 20.000
    final pCheap = await createTestProduct(name: 'Permen Murah', costPrice: 1000, sellPrice: 2000);
    // Produk Mahal: Qty 1 @ Rp 50.000 = Omzet Rp 50.000
    final pExpensive = await createTestProduct(name: 'Steak Premium', costPrice: 30000, sellPrice: 50000);

    await insertSaleRecord(
      invoiceNo: 'INV-SORT',
      total: 70000,
      cashierId: ownerUser.id,
      createdAt: now,
      items: [
        (productId: pCheap, name: 'Permen Murah', qty: 10, price: 2000, costPrice: 1000),
        (productId: pExpensive, name: 'Steak Premium', qty: 1, price: 50000, costPrice: 30000),
      ],
      payments: [(method: 'cash', amount: 70000)],
    );

    // Urutkan by revenue
    final reportRevenue = await reportRepo.getFullReport(
      from: todayStart,
      to: todayEnd,
      topSellingSortBy: 'revenue',
    );
    expect(reportRevenue.topProducts.first.productName, equals('Steak Premium'));
    expect(reportRevenue.topProducts.first.totalRevenue, equals(50000));

    // Urutkan by qty
    final reportQty = await reportRepo.getFullReport(
      from: todayStart,
      to: todayEnd,
      topSellingSortBy: 'qty',
    );
    expect(reportQty.topProducts.first.productName, equals('Permen Murah'));
    expect(reportQty.topProducts.first.totalQty, equals(10));
  });

  test('12. Mode Solo menyembunyikan laporan kasir, Mode Tim menampilkan kinerja kasir', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    final pId = await createTestProduct(name: 'Barang Tim', costPrice: 5000, sellPrice: 10000);

    // Transaksi Kasir 1
    await insertSaleRecord(
      invoiceNo: 'INV-CASHIER-1',
      total: 20000,
      cashierId: cashierUser.id,
      createdAt: now,
      items: [(productId: pId, name: 'Barang Tim', qty: 2, price: 10000, costPrice: 5000)],
      payments: [(method: 'cash', amount: 20000)],
    );

    // Kasus 1: Mode Solo
    final soloReport = await reportRepo.getFullReport(
      from: todayStart,
      to: todayEnd,
      isSoloMode: true,
    );
    expect(soloReport.cashierSales, isNull);

    // Kasus 2: Mode Tim (isSoloMode = false)
    final teamReport = await reportRepo.getFullReport(
      from: todayStart,
      to: todayEnd,
      isSoloMode: false,
    );
    expect(teamReport.cashierSales, isNotNull);
    expect(teamReport.cashierSales!.first.cashierId, equals(cashierUser.id));
    expect(teamReport.cashierSales!.first.cashierName, equals(cashierUser.displayName));
    expect(teamReport.cashierSales!.first.totalRevenue, equals(20000));
    expect(teamReport.cashierSales!.first.txCount, equals(1));
  });

  test('13. Laporan per jam (hourlySales) memetakan transaksi 24 jam', () async {
    featureGate.tier.value = Tier.semi;
    final baseDate = DateTime(2026, 10, 19, 0, 0, 0);
    final from = baseDate;
    final to = DateTime(2026, 10, 20, 0, 0, 0);

    final pId = await createTestProduct(name: 'Item Jam', costPrice: 1000, sellPrice: 5000);

    // Jam 09:00 (1 tx)
    await insertSaleRecord(
      invoiceNo: 'INV-H09',
      total: 5000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 19, 9, 30, 0),
      items: [(productId: pId, name: 'Item Jam', qty: 1, price: 5000, costPrice: 1000)],
    );

    // Jam 13:00 (2 tx)
    await insertSaleRecord(
      invoiceNo: 'INV-H13-1',
      total: 10000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 19, 13, 15, 0),
      items: [(productId: pId, name: 'Item Jam', qty: 2, price: 5000, costPrice: 1000)],
    );
    await insertSaleRecord(
      invoiceNo: 'INV-H13-2',
      total: 15000,
      cashierId: ownerUser.id,
      createdAt: DateTime(2026, 10, 19, 13, 45, 0),
      items: [(productId: pId, name: 'Item Jam', qty: 3, price: 5000, costPrice: 1000)],
    );

    final report = await reportRepo.getFullReport(from: from, to: to);
    expect(report.hourlySales.length, equals(24));

    final h9 = report.hourlySales.firstWhere((h) => h.hour == 9);
    expect(h9.txCount, equals(1));
    expect(h9.totalRevenue, equals(5000));

    final h13 = report.hourlySales.firstWhere((h) => h.hour == 13);
    expect(h13.txCount, equals(2));
    expect(h13.totalRevenue, equals(25000));

    final emptyH = report.hourlySales.firstWhere((h) => h.hour == 0);
    expect(emptyH.txCount, equals(0));
    expect(emptyH.totalRevenue, equals(0));
  });

  test('14. Valuasi nilai modal stok dan peringatan stok menipis/habis akurat', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();

    // Produk 1: Stok Habis (stok 0)
    await createTestProduct(
      name: 'Produk Habis',
      costPrice: 5000,
      sellPrice: 10000,
      currentStock: 0,
      minStock: 5,
    );

    // Produk 2: Stok Menipis (stok 3 <= minStock 5)
    await createTestProduct(
      name: 'Produk Menipis',
      costPrice: 4000,
      sellPrice: 8000,
      currentStock: 3,
      minStock: 5,
    );

    // Produk 3: Stok Aman (stok 20 > minStock 5)
    await createTestProduct(
      name: 'Produk Aman',
      costPrice: 10000,
      sellPrice: 15000,
      currentStock: 20,
      minStock: 5,
    );

    final report = await reportRepo.getFullReport(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day + 1),
    );

    // Stok alerts
    expect(report.stockAlerts.outOfStockCount, equals(1));
    expect(report.stockAlerts.outOfStockProducts.first.name, equals('Produk Habis'));

    expect(report.stockAlerts.lowStockCount, equals(1));
    expect(report.stockAlerts.lowStockProducts.first.name, equals('Produk Menipis'));

    // Valuasi stok
    final val = report.stockValuation;
    expect(val, isNotNull);
    expect(val!.totalStockQty, equals(23));
    expect(val.totalCostValue, equals(212000));
    expect(val.totalRetailValue, equals(324000));
    expect(val.potentialProfit, equals(112000));
  });

  test('15. Ringkasan void merangkum transaksi dibatalkan tanpa mengotori omzet', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    final pId = await createTestProduct(name: 'Barang Void Test', costPrice: 5000, sellPrice: 10000);

    // Transaksi Sukses: 50.000
    await insertSaleRecord(
      invoiceNo: 'INV-COMPLETED',
      total: 50000,
      cashierId: ownerUser.id,
      createdAt: now,
      status: 'completed',
      items: [(productId: pId, name: 'Barang Void Test', qty: 5, price: 10000, costPrice: 5000)],
    );

    // Transaksi Void 1: 20.000
    await insertSaleRecord(
      invoiceNo: 'INV-VOID-1',
      total: 20000,
      cashierId: ownerUser.id,
      createdAt: now,
      status: 'void',
      items: [(productId: pId, name: 'Barang Void Test', qty: 2, price: 10000, costPrice: 5000)],
    );

    // Transaksi Void 2: 30.000
    await insertSaleRecord(
      invoiceNo: 'INV-VOID-2',
      total: 30000,
      cashierId: ownerUser.id,
      createdAt: now,
      status: 'void',
      items: [(productId: pId, name: 'Barang Void Test', qty: 3, price: 10000, costPrice: 5000)],
    );

    final report = await reportRepo.getFullReport(from: todayStart, to: todayEnd);

    // Void TIDAK masuk ke omzet
    expect(report.summary.omzet, equals(50000));
    expect(report.summary.txCount, equals(1));

    // Void Summary mencatat jumlah dan nilai transaksi void
    expect(report.voidSummary.voidCount, equals(2));
    expect(report.voidSummary.totalVoidAmount, equals(50000)); // 20.000 + 30.000
  });

  test('16. User tanpa izin report.view_profit menyensor HPP, laba kotor, dan modal stok pada getFullReport', () async {
    featureGate.tier.value = Tier.semi;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    final pId = await createTestProduct(name: 'Barang Rahasia', costPrice: 5000, sellPrice: 10000, currentStock: 10);

    await insertSaleRecord(
      invoiceNo: 'INV-SENSOR',
      total: 20000,
      cashierId: cashierUser.id,
      createdAt: now,
      items: [(productId: pId, name: 'Barang Rahasia', qty: 2, price: 10000, costPrice: 5000)],
      payments: [(method: 'cash', amount: 20000)],
    );

    // Berikan izin report.view_basic ke kasir, tapi JANGAN berikan report.view_profit
    await roleRepo.addPermission(
      RolePermissionsCompanion(
        roleId: drift.Value(cashierRoleId),
        permissionKey: const drift.Value(PermissionKeys.reportViewBasic),
      ),
    );

    // Ubah toko ke multi-user dan login sebagai Kasir (tidak punya report.view_profit)
    await storeDao.updateStore(
      const StoresCompanion(
        id: drift.Value(1),
        name: drift.Value('Toko Sukses Makmur'),
        mode: drift.Value('multi_user'),
        requireLogin: drift.Value(true),
      ),
    );
    AuthService.to.currentUser.value = cashierUser;
    await AuthService.to.refreshState();
    await permissionService.refreshPermissions();

    expect(permissionService.can(PermissionKeys.reportViewBasic), isTrue);
    expect(permissionService.can(PermissionKeys.reportViewProfit), isFalse);

    final report = await reportRepo.getFullReport(from: todayStart, to: todayEnd);

    // Omzet dan jumlah transaksi tetap terlihat
    expect(report.isProfitVisible, isFalse);
    expect(report.summary.omzet, equals(20000));
    expect(report.summary.txCount, equals(1));

    // Angka sensitif disensor menjadi NULL
    expect(report.summary.cogs, isNull);
    expect(report.summary.grossProfit, isNull);
    expect(report.topProducts.first.totalCost, isNull);
    expect(report.topProducts.first.grossProfit, isNull);
    expect(report.stockValuation?.totalCostValue, isNull);
    expect(report.stockValuation?.potentialProfit, isNull);

    // Angka non-sensitif stok tetap tersedia
    expect(report.stockValuation?.totalStockQty, equals(10));
    expect(report.stockValuation?.totalRetailValue, equals(100000));
  });
}
