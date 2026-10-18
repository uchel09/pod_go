// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_dao.dart';

// ignore_for_file: type=lint
mixin _$StoreDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoresTable get stores => attachedDatabase.stores;
  StoreDaoManager get managers => StoreDaoManager(this);
}

class StoreDaoManager {
  final _$StoreDaoMixin _db;
  StoreDaoManager(this._db);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
}
