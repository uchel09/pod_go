import 'package:drift/drift.dart';
import 'sales.dart';
import 'users.dart';

@TableIndex(name: 'sale_returns_created_at_idx', columns: {#createdAt})
class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  TextColumn get returnNo => text().unique()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get subtotal => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get taxRefund => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get total => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get creditRefund => integer().withDefault(const Constant(0))(); // Rupiah int (pengurangan kasbon)
  TextColumn get refundMethod => text().withDefault(const Constant('cash'))(); // cash / other
  TextColumn get reason => text()();
  IntColumn get createdBy => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

