import 'package:get/get.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/role_repository.dart';
import '../services/auth_service.dart';

/// Layanan manajemen hak akses pengguna (Role-Based Access Control).
class PermissionService extends GetxService {
  static PermissionService get to => Get.find<PermissionService>();

  final RoleRepository _roleRepo;

  PermissionService(this._roleRepo);

  /// Kumpulan kunci permission yang dimiliki oleh user yang sedang aktif
  final RxSet<String> currentPermissions = <String>{}.obs;

  /// Data role dari user aktif
  final Rxn<Role> currentRole = Rxn<Role>();

  Future<PermissionService> init() async {
    if (Get.isRegistered<AuthService>()) {
      ever(AuthService.to.currentUser, (_) => refreshPermissions());
    }
    await refreshPermissions();
    return this;
  }

  /// Memuat ulang hak akses berdasarkan user aktif
  Future<void> refreshPermissions() async {
    if (!Get.isRegistered<AuthService>()) {
      currentPermissions.clear();
      currentRole.value = null;
      return;
    }

    final user = AuthService.to.currentUser.value;
    if (user == null) {
      currentPermissions.clear();
      currentRole.value = null;
      return;
    }

    final role = await _roleRepo.getRoleById(user.roleId);
    currentRole.value = role;

    if (role != null) {
      final perms = await _roleRepo.getPermissionsByRole(role.id);
      currentPermissions.assignAll(perms.map((p) => p.permissionKey));
    } else {
      currentPermissions.clear();
    }
  }

  /// Memeriksa apakah user saat ini memiliki izin untuk aksi [permissionKey].
  ///
  /// Aturan:
  /// 1. Pada Mode Solo dengan pemilik (atau tanpa login wajib), selalu bernilai `true`.
  /// 2. Role 'Owner' sistem selalu bernilai `true` untuk semua permission.
  /// 3. Untuk role lainnya, mencocokkan dengan tabel `role_permissions`.
  bool can(String permissionKey) {
    if (!Get.isRegistered<AuthService>()) return false;

    final auth = AuthService.to;

    // 1. Mode Solo dengan owner / tanpa login -> selalu true
    if (auth.isSoloMode) {
      return true;
    }

    // 2. Role Owner sistem -> selalu true
    if (currentRole.value?.name.toLowerCase() == 'owner') {
      return true;
    }

    // 3. Cek daftar izin aktif
    return currentPermissions.contains(permissionKey);
  }
}

