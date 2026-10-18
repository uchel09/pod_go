import '../local/app_database.dart';
import '../local/daos/settings_dao.dart';

class SettingsRepository {
  final SettingsDao _dao;

  SettingsRepository(this._dao);

  Future<List<AppSetting>> getAllSettings() => _dao.getAllSettings();
  Stream<List<AppSetting>> watchAllSettings() => _dao.watchAllSettings();
  Future<String?> getSetting(String key) => _dao.getSetting(key);
  Future<int> setSetting(String key, String value) => _dao.setSetting(key, value);
  Future<int> deleteSetting(String key) => _dao.deleteSetting(key);
}

