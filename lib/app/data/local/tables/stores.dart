import 'package:drift/drift.dart';

class Stores extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('solo'))(); // solo / team
  BoolColumn get requireLogin => boolean().withDefault(const Constant(false))();
  TextColumn get scannerType => text().withDefault(const Constant('1d'))(); // 1d / 2d
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

