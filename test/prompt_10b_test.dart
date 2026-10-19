import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/audit/audit_actions.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/local/daos/audit_dao.dart';
import 'package:pos_me/app/data/local/daos/product_dao.dart';
import 'package:pos_me/app/data/local/daos/stock_dao.dart';
import 'package:pos_me/app/data/repositories/audit_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditDao auditDao;
  late AuditRepository auditRepo;
  late ProductDao productDao;
  late StockDao stockDao;
  late StockRepository stockRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditDao = db.auditDao;
    auditRepo = AuditRepository(auditDao);
    productDao = db.productDao;
    stockDao = db.stockDao;
    stockRepo = StockRepository(db, stockDao, productDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 10B Tests: Audit Log Append-Only & Catalog', () {
    test('Audit actions formatting and sanitization works as expected', () {
      final sanitized = AuditActions.sanitizeDetail({
        'name': 'Kopi',
        'password': 'secretPassword',
        'pin': '1234',
        'costPrice': 5000,
      });
      expect(sanitized.containsKey('password'), isFalse);
      expect(sanitized.containsKey('pin'), isFalse);
      expect(sanitized['name'], 'Kopi');
      expect(sanitized['costPrice'], 5000);

      final sentence = AuditActions.formatHumanSentence(
        action: AuditActions.productPriceChange,
        userName: 'Budi',
        detail: {'productName': 'Indomie', 'oldPrice': 3000, 'newPrice': 3500},
      );
      expect(sentence.contains('Budi'), isTrue);
      expect(sentence.contains('Indomie'), isTrue);
    });

    test('AuditDao is append-only and pagination works', () async {
      await auditDao.insertLog(AuditLogsCompanion.insert(
        action: AuditActions.authLogin,
        entity: 'auth',
        detail: const Value('{"status":"ok"}'),
        deviceId: 'device-test-1',
      ));
      await auditDao.insertLog(AuditLogsCompanion.insert(
        action: AuditActions.productCreate,
        entity: 'products',
        entityId: const Value(1),
        detail: const Value('{"name":"Es Teh"}'),
        deviceId: 'device-test-1',
      ));

      final logs = await auditRepo.getLogsPage(limit: 10);
      expect(logs.length, 2);
      expect(logs.first.action, AuditActions.productCreate); // sorted desc
    });
  });

  group('Prompt 10B Tests: Stock Adjustments & Validation', () {
    test('Penyesuaian stok manual: validasi mode add dan set, tolak selisih 0', () async {
      final productId = await productDao.insertProduct(const ProductsCompanion(
        name: Value('Susu UHT'),
        costPrice: Value(4000),
        sellPrice: Value(6000),
        currentStock: Value(10),
      ));

      // 1. Tambah stok
      await stockRepo.adjustStock(
        productId: productId,
        mode: 'add',
        qty: 5,
        reason: 'lainnya',
        note: 'Stok bonus supplier',
      );
      var p = await productDao.getProductById(productId);
      expect(p?.currentStock, 15);

      // 2. Set stok utuh
      await stockRepo.adjustStock(
        productId: productId,
        mode: 'set',
        qty: 12,
        reason: 'rusak',
      );
      p = await productDao.getProductById(productId);
      expect(p?.currentStock, 12);

      // 3. Set stok sama (selisih nol) harus throw AppException
      expect(
        () => stockRepo.adjustStock(
          productId: productId,
          mode: 'set',
          qty: 12,
          reason: 'rusak',
        ),
        throwsA(isA<AppException>()),
      );

      // 4. Alasan lainnya wajib note minimal 5 karakter
      expect(
        () => stockRepo.adjustStock(
          productId: productId,
          mode: 'add',
          qty: 2,
          reason: 'lainnya',
          note: 'abc', // < 5 karakter
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('Kartu stok running balance dihitung via window function SUM() OVER()', () async {
      final productId = await productDao.insertProduct(const ProductsCompanion(
        name: Value('Biskuit Roma'),
        costPrice: Value(5000),
        sellPrice: Value(7000),
        currentStock: Value(0),
      ));

      await stockRepo.applyMovement(
        productId: productId,
        type: 'purchase',
        qtyChange: 20,
        note: 'Beli awal',
      );
      await stockRepo.applyMovement(
        productId: productId,
        type: 'sale',
        qtyChange: -5,
        note: 'Terjual 5',
      );
      await stockRepo.applyMovement(
        productId: productId,
        type: 'adjustment',
        qtyChange: -2,
        note: 'Rusak',
      );

      final page = await stockDao.getStockCardPage(productId: productId, limit: 10);
      expect(page.length, 3);
      // Diurutkan createdAt DESC
      expect(page[0].qtyChange, -2);
      expect(page[0].stockAfter, 13);

      expect(page[1].qtyChange, -5);
      expect(page[1].stockAfter, 15);

      expect(page[2].qtyChange, 20);
      expect(page[2].stockAfter, 20);
    });
  });
}
