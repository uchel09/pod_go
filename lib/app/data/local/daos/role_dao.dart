import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/role_permissions.dart';
import '../tables/roles.dart';

part 'role_dao.g.dart';

@DriftAccessor(tables: [Roles, RolePermissions])
class RoleDao extends DatabaseAccessor<AppDatabase> with _$RoleDaoMixin {
  RoleDao(super.db);

  Future<List<Role>> getAllRoles() => select(roles).get();

  Stream<List<Role>> watchAllRoles() => select(roles).watch();

  Future<Role?> getRoleById(int id) =>
      (select(roles)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Role?> getRoleByName(String name) =>
      (select(roles)..where((t) => t.name.equals(name))).getSingleOrNull();

  Future<int> insertRole(RolesCompanion role) => into(roles).insert(role);

  Future<bool> updateRole(RolesCompanion role) => update(roles).replace(role);

  Future<int> deleteRole(int id) => (delete(roles)..where((t) => t.id.equals(id))).go();

  Future<List<RolePermission>> getPermissionsByRole(int roleId) =>
      (select(rolePermissions)..where((t) => t.roleId.equals(roleId))).get();

  Future<int> addPermission(RolePermissionsCompanion permission) =>
      into(rolePermissions).insert(permission);

  Future<int> deletePermission(int id) =>
      (delete(rolePermissions)..where((t) => t.id.equals(id))).go();
}

