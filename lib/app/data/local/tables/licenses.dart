import 'package:drift/drift.dart';

class Licenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tier => text().withDefault(const Constant('free'))(); // free / semi / premium
  TextColumn get source => text().withDefault(const Constant('simulated'))(); // simulated / offline_key / store / backend
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get issuedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

