import 'package:drift/drift.dart';
import 'sales.dart';

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  TextColumn get method => text()(); // cash / qris / transfer / other / credit
  IntColumn get amount => integer()(); // Rupiah int
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

