import 'package:drift/drift.dart';

import '../../core/permissions/permission_keys.dart';
import '../local/app_database.dart';
import '../repositories/role_repository.dart';

/// Seeder role bawaan sistem (idempotent, aman dijalankan berulang kali).
class RoleSeeder {
  RoleSeeder._();

  /// Daftar role bawaan beserta konfigurasi dan permission standarnya
  static final Map<String, ({String description, bool isLocked, List<String> permissions})>
      _defaultRoles = {
    'Owner': (
      description: 'Pemilik Toko (Akses Penuh)',
      isLocked: true,
      permissions: PermissionKeys.all,
    ),
    'Admin': (
      description: 'Administrator Operasional',
      isLocked: false,
      permissions: PermissionKeys.all.where((k) => ![
            PermissionKeys.settingsManage,
            PermissionKeys.backupManage,
            PermissionKeys.licenseManage,
            PermissionKeys.roleManage,
          ].contains(k)).toList(),
    ),
    'Kasir': (
      description: 'Kasir Penjualan',
      isLocked: false,
      permissions: [
        PermissionKeys.posSell,
        PermissionKeys.posDiscount,
        PermissionKeys.productView,
        PermissionKeys.stockView,
        PermissionKeys.attendanceSelf,
      ],
    ),
    'Gudang': (
      description: 'Pengelola Gudang & Stok',
      isLocked: false,
      permissions: [
        PermissionKeys.productView,
        PermissionKeys.productEdit,
        PermissionKeys.stockView,
        PermissionKeys.stockAdjust,
        PermissionKeys.stockPurchase,
        PermissionKeys.stockOpname,
        PermissionKeys.attendanceSelf,
      ],
    ),
    'Crew': (
      description: 'Staf Lapangan / Pelayan',
      isLocked: false,
      permissions: [
        PermissionKeys.productView,
        PermissionKeys.stockView,
        PermissionKeys.attendanceSelf,
      ],
    ),
  };

  /// Menyemai role dan permission standar ke database secara idempotent
  static Future<void> seedDefaultRoles(RoleRepository roleRepo) async {
    for (final entry in _defaultRoles.entries) {
      final roleName = entry.key;
      final config = entry.value;

      // 1. Dapatkan atau buat Role
      var role = await roleRepo.getRoleByName(roleName);
      if (role == null) {
        final roleId = await roleRepo.insertRole(
          RolesCompanion(
            name: Value(roleName),
            description: Value(config.description),
            isSystem: const Value(true),
            isLocked: Value(config.isLocked),
          ),
        );
        role = await roleRepo.getRoleById(roleId);
      }

      if (role == null) continue;

      // 2. Periksa permission yang sudah tersimpan untuk role ini
      final existingPerms = await roleRepo.getPermissionsByRole(role.id);
      final existingKeys = existingPerms.map((p) => p.permissionKey).toSet();

      // 3. Masukkan permission yang belum ada
      for (final permKey in config.permissions) {
        if (!existingKeys.contains(permKey)) {
          await roleRepo.addPermission(
            RolePermissionsCompanion(
              roleId: Value(role.id),
              permissionKey: Value(permKey),
            ),
          );
        }
      }
    }
  }
}

