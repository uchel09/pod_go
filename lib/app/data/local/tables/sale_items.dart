import 'package:drift/drift.dart';
import 'products.dart';
import 'sales.dart';

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get productName => text()(); // snapshot
  IntColumn get qty => integer().withDefault(const Constant(1))();
  IntColumn get price => integer().withDefault(const Constant(0))(); // snapshot, Rupiah int
  IntColumn get costPrice => integer().withDefault(const Constant(0))(); // snapshot, Rupiah int
  IntColumn get discount => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get subtotal => integer().withDefault(const Constant(0))(); // Rupiah int
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

