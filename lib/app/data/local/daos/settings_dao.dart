import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_settings.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<List<AppSetting>> getAllSettings() => select(appSettings).get();

  Stream<List<AppSetting>> watchAllSettings() => select(appSettings).watch();

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<int> setSetting(String key, String value) async {
    final existing = await (select(appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    if (existing != null) {
      await (update(appSettings)..where((t) => t.key.equals(key))).write(
        AppSettingsCompanion(
          value: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return existing.id;
    } else {
      return into(appSettings).insert(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
        ),
      );
    }
  }

  Future<int> deleteSetting(String key) =>
      (delete(appSettings)..where((t) => t.key.equals(key))).go();

  /// Mengambil counter bilangan bulat dan menaikkannya secara atomik
  Future<int> getNextCounter(String key, {int defaultValue = 1}) async {
    final currentStr = await getSetting(key);
    final current = currentStr != null ? (int.tryParse(currentStr) ?? defaultValue) : defaultValue;
    await setSetting(key, (current + 1).toString());
    return current;
  }
}

