import 'package:drift/drift.dart';
import 'products.dart';
import 'sale_items.dart';
import 'sale_returns.dart';

class SaleReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(SaleReturns, #id)();
  IntColumn get saleItemId => integer().references(SaleItems, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get productName => text()(); // snapshot
  IntColumn get qty => integer().withDefault(const Constant(1))();
  IntColumn get unitPrice =>
      integer().withDefault(const Constant(0))(); // snapshot, Rupiah int
  IntColumn get costPrice =>
      integer().withDefault(const Constant(0))(); // snapshot, Rupiah int
  BoolColumn get restock => boolean().withDefault(const Constant(true))();
  IntColumn get subtotal =>
      integer().withDefault(const Constant(0))(); // Rupiah int
}
