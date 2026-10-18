// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'license_dao.dart';

// ignore_for_file: type=lint
mixin _$LicenseDaoMixin on DatabaseAccessor<AppDatabase> {
  $LicensesTable get licenses => attachedDatabase.licenses;
  LicenseDaoManager get managers => LicenseDaoManager(this);
}

class LicenseDaoManager {
  final _$LicenseDaoMixin _db;
  LicenseDaoManager(this._db);
  $$LicensesTableTableManager get licenses =>
      $$LicensesTableTableManager(_db.attachedDatabase, _db.licenses);
}
