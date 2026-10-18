import 'package:drift/drift.dart';
import 'products.dart';
import 'users.dart';

class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get type => text()(); // sale / purchase / opname / void / adjustment
  IntColumn get qtyChange => integer()(); // e.g. +5 or -2
  TextColumn get refTable => text().nullable()();
  IntColumn get refId => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

