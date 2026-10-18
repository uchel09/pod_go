import 'package:drift/drift.dart';
import 'products.dart';
import 'stock_opnames.dart';

class StockOpnameItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get opnameId => integer().references(StockOpnames, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get systemQty => integer()();
  IntColumn get countedQty => integer()();
  IntColumn get difference => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

