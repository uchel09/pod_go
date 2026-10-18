import 'package:drift/drift.dart';
import 'products.dart';
import 'purchases.dart';

class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get qty => integer().withDefault(const Constant(1))();
  IntColumn get costPrice => integer().withDefault(const Constant(0))(); // Rupiah int
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

