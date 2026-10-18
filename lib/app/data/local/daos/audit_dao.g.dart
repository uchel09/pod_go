// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_dao.dart';

// ignore_for_file: type=lint
mixin _$AuditDaoMixin on DatabaseAccessor<AppDatabase> {
  $RolesTable get roles => attachedDatabase.roles;
  $UsersTable get users => attachedDatabase.users;
  $AuditLogsTable get auditLogs => attachedDatabase.auditLogs;
  AuditDaoManager get managers => AuditDaoManager(this);
}

class AuditDaoManager {
  final _$AuditDaoMixin _db;
  AuditDaoManager(this._db);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$AuditLogsTableTableManager get auditLogs =>
      $$AuditLogsTableTableManager(_db.attachedDatabase, _db.auditLogs);
}
