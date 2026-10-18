// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_dao.dart';

// ignore_for_file: type=lint
mixin _$RoleDaoMixin on DatabaseAccessor<AppDatabase> {
  $RolesTable get roles => attachedDatabase.roles;
  $RolePermissionsTable get rolePermissions => attachedDatabase.rolePermissions;
  RoleDaoManager get managers => RoleDaoManager(this);
}

class RoleDaoManager {
  final _$RoleDaoMixin _db;
  RoleDaoManager(this._db);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$RolePermissionsTableTableManager get rolePermissions =>
      $$RolePermissionsTableTableManager(
        _db.attachedDatabase,
        _db.rolePermissions,
      );
}
