import 'package:drift/drift.dart';
import 'users.dart';

class StockOpnames extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  TextColumn get code => text().unique()();
  DateTimeColumn get date => dateTime()();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft / final
  TextColumn get note => text().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

