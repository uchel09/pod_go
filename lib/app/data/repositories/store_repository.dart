import 'package:get/get.dart';

import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/store_dao.dart';

class StoreRepository {
  final StoreDao _dao;

  StoreRepository(this._dao);

  void _assertSettingsManageAccess() {
    if (Get.isRegistered<PermissionService>() &&
        Get.isRegistered<AuthService>()) {
      final auth = AuthService.to;
      if (auth.hasStore && !auth.isSoloMode) {
        if (!PermissionService.to.can(PermissionKeys.settingsManage)) {
          throw const AppException(
            'Akses ditolak: Anda tidak memiliki izin untuk mengelola pengaturan toko (settings.manage).',
            code: 'FORBIDDEN',
          );
        }
      }
    }
  }

  Future<Store?> getStore() => _dao.getStore();
  Stream<Store?> watchStore() => _dao.watchStore();
  Future<int> insertStore(StoresCompanion store) => _dao.insertStore(store);

  Future<bool> updateStore(StoresCompanion store) {
    _assertSettingsManageAccess();
    return _dao.updateStore(store);
  }

  Future<int> deleteStore(int id) {
    _assertSettingsManageAccess();
    return _dao.deleteStore(id);
  }
}
