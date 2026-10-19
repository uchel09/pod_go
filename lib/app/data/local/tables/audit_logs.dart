import 'package:drift/drift.dart';
import 'users.dart';

@TableIndex(name: 'audit_logs_created_at_idx', columns: {#createdAt})
@TableIndex(name: 'audit_logs_entity_idx', columns: {#entity, #entityId})
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get detail => text().nullable()(); // JSON text
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

