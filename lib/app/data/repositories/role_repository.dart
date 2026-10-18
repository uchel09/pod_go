import '../local/app_database.dart';
import '../local/daos/role_dao.dart';

class RoleRepository {
  final RoleDao _dao;

  RoleRepository(this._dao);

  Future<List<Role>> getAllRoles() => _dao.getAllRoles();
  Stream<List<Role>> watchAllRoles() => _dao.watchAllRoles();
  Future<Role?> getRoleById(int id) => _dao.getRoleById(id);
  Future<Role?> getRoleByName(String name) => _dao.getRoleByName(name);
  Future<int> insertRole(RolesCompanion role) => _dao.insertRole(role);
  Future<bool> updateRole(RolesCompanion role) => _dao.updateRole(role);
  Future<int> deleteRole(int id) => _dao.deleteRole(id);
  Future<List<RolePermission>> getPermissionsByRole(int roleId) => _dao.getPermissionsByRole(roleId);
  Future<int> addPermission(RolePermissionsCompanion permission) => _dao.addPermission(permission);
  Future<int> deletePermission(int id) => _dao.deletePermission(id);
}

