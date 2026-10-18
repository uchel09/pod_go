import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/categories.dart';
import '../tables/products.dart';
import '../tables/units.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products, Categories, Units])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Future<List<Product>> getAllProducts() => select(products).get();

  Stream<List<Product>> watchAllProducts() => select(products).watch();

  Future<Product?> getProductById(int id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Product?> getProductByBarcode(String barcode) =>
      (select(products)..where((t) => t.barcode.equals(barcode))).getSingleOrNull();

  Future<int> insertProduct(ProductsCompanion product) => into(products).insert(product);

  Future<bool> updateProduct(ProductsCompanion product) => update(products).replace(product);

  Future<int> deleteProduct(int id) =>
      (delete(products)..where((t) => t.id.equals(id))).go();

  Future<int> updateProductStock(int id, int newStock) {
    return (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        currentStock: Value(newStock),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> countProductsByCategoryId(int categoryId) async {
    final list = await (select(products)..where((t) => t.categoryId.equals(categoryId))).get();
    return list.length;
  }

  Future<int> countProductsByUnitId(int unitId) async {
    final list = await (select(products)..where((t) => t.unitId.equals(unitId))).get();
    return list.length;
  }

  Future<Product?> getProductByInternalCode(String internalCode) =>
      (select(products)..where((t) => t.internalCode.equals(internalCode))).getSingleOrNull();

  Future<Product?> getProductBySku(String sku) =>
      (select(products)..where((t) => t.sku.equals(sku))).getSingleOrNull();

  Future<Product?> getProductByBarcodeOrInternalCode(String code) =>
      (select(products)..where((t) => t.barcode.equals(code) | t.internalCode.equals(code))).getSingleOrNull();

  Future<List<Product>> getActiveProductsOrderedByCreatedAt() =>
      (select(products)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
          .get();

  Stream<List<Product>> watchActiveProductsOrderedByCreatedAt() =>
      (select(products)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
          .watch();

  Future<int> countActiveProducts() async {
    final list = await (select(products)..where((t) => t.isActive.equals(true))).get();
    return list.length;
  }

  Stream<int> watchActiveProductsCount() =>
      (select(products)..where((t) => t.isActive.equals(true))).watch().map((list) => list.length);

  Future<int> setProductActive(int id, bool isActive) {
    return (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

