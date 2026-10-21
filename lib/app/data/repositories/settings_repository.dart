import 'package:get/get.dart';

import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/settings_dao.dart';

class SettingsRepository {
  final SettingsDao _dao;

  SettingsRepository(this._dao);

  void _assertSettingsManageAccess() {
    if (Get.isRegistered<PermissionService>() &&
        Get.isRegistered<AuthService>()) {
      final auth = AuthService.to;
      if (auth.hasStore && !auth.isSoloMode) {
        if (!PermissionService.to.can(PermissionKeys.settingsManage)) {
          throw const AppException(
            'Akses ditolak: Anda tidak memiliki izin untuk mengelola pengaturan (settings.manage).',
            code: 'FORBIDDEN',
          );
        }
      }
    }
  }

  Future<List<AppSetting>> getAllSettings() => _dao.getAllSettings();
  Stream<List<AppSetting>> watchAllSettings() => _dao.watchAllSettings();
  Future<String?> getSetting(String key) => _dao.getSetting(key);

  Future<int> setSetting(String key, String value) {
    if (key.startsWith('printer.') ||
        key.startsWith('store.') ||
        key.startsWith('receipt.') ||
        key.startsWith('tax.') ||
        key == 'receipt_footer' ||
        key == 'pos.allow_negative_stock' ||
        key == 'pos.receipt_width' ||
        key == 'audit_discount_threshold') {
      _assertSettingsManageAccess();
    }
    return _dao.setSetting(key, value);
  }

  Future<int> deleteSetting(String key) {
    if (key.startsWith('printer.') ||
        key.startsWith('store.') ||
        key.startsWith('receipt.') ||
        key.startsWith('tax.') ||
        key == 'receipt_footer' ||
        key == 'pos.allow_negative_stock' ||
        key == 'pos.receipt_width' ||
        key == 'audit_discount_threshold') {
      _assertSettingsManageAccess();
    }
    return _dao.deleteSetting(key);
  }
}
