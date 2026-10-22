import 'package:drift/drift.dart';

@TableIndex(name: 'customers_name_idx', columns: {#name})
@TableIndex(name: 'customers_phone_idx', columns: {#phone})
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get creditLimit => integer().nullable()(); // Rupiah int (null = tidak terbatas)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

