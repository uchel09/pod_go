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
import 'package:pos_me/app/data/local/daos/report_dao.dart';
import 'package:pos_me/app/data/models/export_models.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/expense_repository.dart';
import 'package:pos_me/app/data/repositories/export_repository.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/report_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/sale_repository.dart';
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
  late ProductRepository productRepo;
  late SaleRepository saleRepo;
  late ExpenseRepository expenseRepo;
  late ExportRepository exportRepo;
  late ReportRepository reportRepo;
  late ReportDao reportDao;
  late AuditRepository auditRepo;
  late PermissionService permService;
  late MockEntitlementProvider entitlementProvider;
  late FeatureGate featureGate;

  late User ownerUser;
  late User staffUser;
  late ExpenseCategory defaultCategory;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'test-expense-dev-001',
    });
    Get.reset();

    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );
    saleRepo = SaleRepository(db, db.saleDao, db.productDao, db.stockDao);
    auditRepo = AuditRepository(db.auditDao);

    // Mock Entitlement default Semi Premium agar fitur pengeluaran terbuka
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

    expenseRepo = ExpenseRepository(
      db,
      db.expenseDao,
      featureGate: featureGate,
      permissionService: permService,
      auditService: auditService,
    );
    Get.put<ExpenseRepository>(expenseRepo, permanent: true);

    reportDao = ReportDao(db);
    reportRepo = ReportRepository(
      reportDao,
      featureGate: featureGate,
      permissionService: permService,
    );
    Get.put<ReportRepository>(reportRepo, permanent: true);

    exportRepo = ExportRepository(
      db: db,
      saleDao: db.saleDao,
      stockDao: db.stockDao,
      opnameDao: db.opnameDao,
      purchaseDao: db.purchaseDao,
      auditDao: db.auditDao,
    );
    Get.put<ExportRepository>(exportRepo, permanent: true);

    await RoleSeeder.seedDefaultRoles(roleRepo);

    // Setup toko
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Pengeluaran Berkah'),
        mode: Value('team'),
        requireLogin: Value(false),
      ),
    );

    // Setup Owner (punya semua izin termasuk expense.view & expense.manage)
    final ownerRole = await roleRepo.getRoleByName('Owner');
    final ownerId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Owner Toko'),
        roleId: Value(ownerRole!.id),
      ),
    );
    ownerUser = (await userRepo.getUserById(ownerId))!;

    // Setup Kasir biasa (tidak punya izin expense.view maupun expense.manage)
    final cashierRole = await roleRepo.getRoleByName('Kasir');
    final staffId = await userRepo.insertUser(
      UsersCompanion(
        username: const Value('staff_kasir'),
        displayName: const Value('Staff Kasir'),
        roleId: Value(cashierRole!.id),
      ),
    );
    staffUser = (await userRepo.getUserById(staffId))!;

    AuthService.to.currentUser.value = ownerUser;
    await permService.refreshPermissions();

    // Pastikan seeder default kategori pengeluaran dijalankan
    await db.expenseDao.seedDefaultCategories();
    final cats = await db.expenseDao.getActiveCategories();
    defaultCategory = cats.firstWhere((c) => c.name == 'Listrik');
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  group('PROMPT 20: Pengeluaran Operasional & Laba Bersih Tests', () {
    test('1. Nominal pengeluaran <= 0 ditolak dengan INVALID_AMOUNT', () async {
      expect(
        () async => await expenseRepo.createExpense(
          CreateExpenseInput(
            date: DateTime.now(),
            categoryId: defaultCategory.id,
            amount: 0,
            note: 'Pengeluaran nol',
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('INVALID_AMOUNT'))),
      );

      expect(
        () async => await expenseRepo.createExpense(
          CreateExpenseInput(
            date: DateTime.now(),
            categoryId: defaultCategory.id,
            amount: -50000,
            note: 'Pengeluaran negatif',
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('INVALID_AMOUNT'))),
      );
    });

    test('2. Catat pengeluaran baru berhasil dan mencatat jejak audit', () async {
      final now = DateTime.now();
      final item = await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 250000,
          note: 'Token PLN 250rb',
          paymentMethod: 'cash',
        ),
      );

      expect(item.amount, equals(250000));
      expect(item.categoryName, equals('Listrik'));
      expect(item.status, equals('active'));
      expect(item.isVoided, isFalse);

      // Cek jejak audit
      final logs = await auditRepo.getAllLogs();
      expect(logs.any((l) => l.action == 'expense.create'), isTrue);
    });

    test('3. Ubah pengeluaran berhasil dan mencatat audit diff', () async {
      final now = DateTime.now();
      final created = await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 200000,
          note: 'Sewa lapak',
        ),
      );

      final updated = await expenseRepo.updateExpense(
        UpdateExpenseInput(
          id: created.id,
          date: now,
          categoryId: defaultCategory.id,
          amount: 300000,
          note: 'Sewa lapak + kebersihan',
          paymentMethod: 'transfer',
        ),
      );

      expect(updated.amount, equals(300000));
      expect(updated.note, equals('Sewa lapak + kebersihan'));
      expect(updated.paymentMethod, equals('transfer'));

      // Cek jejak audit update
      final logs = await auditRepo.getAllLogs();
      final updateLog = logs.firstWhere((l) => l.action == 'expense.update');
      expect(updateLog.detail, contains('300000'));
    });

    test('4. Batalkan (void) pengeluaran: status menjadi void dan ada alasan', () async {
      final created = await expenseRepo.createExpense(
        CreateExpenseInput(
          date: DateTime.now(),
          categoryId: defaultCategory.id,
          amount: 150000,
          note: 'Salah catat',
        ),
      );

      await expenseRepo.voidExpense(
        id: created.id,
        reason: 'Nota dobel dari kasir',
      );

      final detail = await db.expenseDao.getExpenseWithCategory(created.id);
      expect(detail!.status, equals('void'));
      expect(detail.isVoided, isTrue);
      expect(detail.voidReason, equals('Nota dobel dari kasir'));
      expect(detail.voidedByName, equals(ownerUser.displayName));

      // Coba void ulang -> ditolak
      expect(
        () async => await expenseRepo.voidExpense(
          id: created.id,
          reason: 'Void ulang',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('5. Pengeluaran void TIDAK dihitung dalam total laporan pengeluaran', () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final end = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

      // Pengeluaran aktif 1 = 100k
      await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 100000,
          note: 'Pengeluaran aktif 1',
        ),
      );

      // Pengeluaran aktif 2 = 50k
      final exp2 = await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 50000,
          note: 'Pengeluaran aktif 2 yang akan dibatalkan',
        ),
      );

      // Pengeluaran aktif 3 = 75k
      await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 75000,
          note: 'Pengeluaran aktif 3',
        ),
      );

      // Batalkan exp2 (50k)
      await expenseRepo.voidExpense(
        id: exp2.id,
        reason: 'Dibatalkan',
      );

      // Total harus: 100k + 75k = 175k (50k void tidak dihitung)
      final total = await expenseRepo.getTotalExpensesForRange(from: start, to: end);
      expect(total, equals(175000));

      final summary = await reportDao.getSummaryForRange(from: start, to: end);
      expect(summary.totalExpenses, equals(175000));
      expect(summary.expenseCount, equals(2));
    });

    test('6. Laba bersih terhitung benar: Laba Bersih = Laba Kotor - Pengeluaran', () async {
      // Setup penjualan: Produk seharga 100k, HPP 60k -> Laba kotor = 40k
      final pId = await productRepo.createProduct(
        const ProductsCompanion(
          name: Value('Barang Uji'),
          sellPrice: Value(100000),
          costPrice: Value(60000),
          currentStock: Value(10),
          isActive: Value(true),
        ),
      );

      await saleRepo.checkout(
        cashierId: ownerUser.id,
        deviceId: 'dev-01',
        items: [
          CheckoutCartItem(
            productId: pId,
            productName: 'Barang Uji',
            qty: 1,
            price: 100000,
            costPrice: 60000,
          ),
        ],
        payments: [
          const CheckoutPayment(method: 'cash', amount: 100000),
        ],
      );

      // Catat pengeluaran 15k
      final now = DateTime.now();
      await expenseRepo.createExpense(
        CreateExpenseInput(
          date: now,
          categoryId: defaultCategory.id,
          amount: 15000,
          note: 'Konsumsi toko',
        ),
      );

      final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final to = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

      final summary = await reportDao.getSummaryForRange(from: from, to: to);

      expect(summary.netSales, equals(100000));
      expect(summary.cogs, equals(60000));
      expect(summary.grossProfit, equals(40000)); // 100k - 60k
      expect(summary.totalExpenses, equals(15000));
      // Laba Bersih = 40000 - 15000 = 25000
      expect(summary.netProfit, equals(25000));
    });

    test('7. Kategori yang sudah pernah digunakan tidak dapat dihapus (CATEGORY_IN_USE)', () async {
      final newCat = await expenseRepo.createCategory('Kategori Khusus Uji');

      // Pakai kategori ini dalam pengeluaran
      await expenseRepo.createExpense(
        CreateExpenseInput(
          date: DateTime.now(),
          categoryId: newCat.id,
          amount: 20000,
          note: 'Uji hapus kategori',
        ),
      );

      // Coba hapus -> Wajib melempar AppException dengan kode CATEGORY_IN_USE
      expect(
        () async => await expenseRepo.deleteCategory(newCat.id),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('CATEGORY_IN_USE'))),
      );

      // Buat kategori lain yang tidak terpakai
      final unusedCat = await expenseRepo.createCategory('Kategori Belum Terpakai');
      await expenseRepo.deleteCategory(unusedCat.id);

      final deleted = await db.expenseDao.getCategoryById(unusedCat.id);
      expect(deleted, isNull);
    });

    test('8. Tier Gratis dan role tanpa izin ditolak di repository', () async {
      // 8A. Tier Gratis ditolak dengan FEATURE_LOCKED
      entitlementProvider.currentMockTier = Tier.free;
      featureGate.tier.value = Tier.free;

      expect(
        () async => await expenseRepo.getAllCategories(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('FEATURE_LOCKED'))),
      );

      expect(
        () async => await expenseRepo.createExpense(
          CreateExpenseInput(
            date: DateTime.now(),
            categoryId: defaultCategory.id,
            amount: 50000,
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('FEATURE_LOCKED'))),
      );

      // 8B. Tier Semi tapi role tanpa izin (Kasir) ditolak dengan FORBIDDEN
      entitlementProvider.currentMockTier = Tier.semi;
      featureGate.tier.value = Tier.semi;
      AuthService.to.currentUser.value = staffUser;
      await permService.refreshPermissions();

      expect(
        () async => await expenseRepo.getAllCategories(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('FORBIDDEN'))),
      );

      expect(
        () async => await expenseRepo.createExpense(
          CreateExpenseInput(
            date: DateTime.now(),
            categoryId: defaultCategory.id,
            amount: 50000,
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', equals('FORBIDDEN'))),
      );
    });

    test('9. Ekspor pengeluaran ke CSV menghasilkan data valid', () async {
      AuthService.to.currentUser.value = ownerUser;
      await permService.refreshPermissions();

      await expenseRepo.createExpense(
        CreateExpenseInput(
          date: DateTime.now(),
          categoryId: defaultCategory.id,
          amount: 80000,
          note: 'Catatan ekspor',
        ),
      );

      final result = await exportRepo.exportExpenses(
        format: ExportFormat.csv,
        from: DateTime.now().subtract(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 1)),
      );

      expect(result.bytes.isNotEmpty, isTrue);
      expect(result.rowCount, greaterThanOrEqualTo(1));
      expect(result.fileName.endsWith('.csv'), isTrue);
    });
  });
}
