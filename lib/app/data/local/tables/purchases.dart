import 'package:drift/drift.dart';
import 'suppliers.dart';

class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  TextColumn get refNo => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get total => integer().withDefault(const Constant(0))(); // Rupiah int
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

