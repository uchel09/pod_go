import 'package:drift/drift.dart';
import 'roles.dart';

class RolePermissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roleId => integer().references(Roles, #id)();
  TextColumn get permissionKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

