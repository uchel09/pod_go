import 'package:drift/drift.dart';
import 'categories.dart';
import 'units.dart';

@TableIndex(name: 'products_barcode_idx', columns: {#barcode})
@TableIndex(name: 'products_name_idx', columns: {#name})
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get internalCode => text().nullable().unique()();
  TextColumn get codeType => text().withDefault(const Constant('manufacturer'))(); // manufacturer / internal_code128 / internal_qr
  TextColumn get name => text()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  IntColumn get costPrice => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get sellPrice => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  IntColumn get currentStock => integer().withDefault(const Constant(0))(); // cache of stock_movements
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

