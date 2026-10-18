import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/stock_repository.dart';

void main() {
  late AppDatabase db;
  late ProductRepository productRepo;
  late StockRepository stockRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    productRepo = ProductRepository(db.productDao);
    stockRepo = StockRepository(db, db.stockDao, db.productDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('insert produk lalu applyMovement(+5) menghasilkan currentStock = 5 dan satu baris stock_movements',
      () async {
    // 1. Insert produk dengan stok awal 0
    final productId = await productRepo.insertProduct(
      const ProductsCompanion(
        name: Value('Kopi Susu Gula Aren'),
        barcode: Value('8991234567890'),
        sellPrice: Value(18000),
        costPrice: Value(10000),
        currentStock: Value(0),
      ),
    );

    // Verifikasi produk tersimpan dengan currentStock = 0
    final initialProduct = await productRepo.getProductById(productId);
    expect(initialProduct, isNotNull);
    expect(initialProduct!.currentStock, 0);

    // 2. Terapkan pergerakan stok (+5)
    await stockRepo.applyMovement(
      productId: productId,
      type: 'purchase',
      qtyChange: 5,
      note: 'Stok awal pembelian',
    );

    // 3. Verifikasi currentStock terupdate menjadi 5
    final updatedProduct = await productRepo.getProductById(productId);
    expect(updatedProduct, isNotNull);
    expect(updatedProduct!.currentStock, 5);

    // 4. Verifikasi baris di tabel stock_movements
    final movements = await stockRepo.getMovementsByProduct(productId);
    expect(movements.length, 1);
    expect(movements.first.productId, productId);
    expect(movements.first.qtyChange, 5);
    expect(movements.first.type, 'purchase');
    expect(movements.first.uuid, isNotEmpty);
  });
}
