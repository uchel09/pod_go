import 'package:drift/drift.dart';
import 'roles.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get passwordHash => text().nullable()();
  TextColumn get pinHash => text().nullable()();
  IntColumn get roleId => integer().references(Roles, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get mustChangePassword => boolean().withDefault(const Constant(false))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  TextColumn get recoveryCodeHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

