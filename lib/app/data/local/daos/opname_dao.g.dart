// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opname_dao.dart';

// ignore_for_file: type=lint
mixin _$OpnameDaoMixin on DatabaseAccessor<AppDatabase> {
  $RolesTable get roles => attachedDatabase.roles;
  $UsersTable get users => attachedDatabase.users;
  $StockOpnamesTable get stockOpnames => attachedDatabase.stockOpnames;
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $StockOpnameItemsTable get stockOpnameItems =>
      attachedDatabase.stockOpnameItems;
  OpnameDaoManager get managers => OpnameDaoManager(this);
}

class OpnameDaoManager {
  final _$OpnameDaoMixin _db;
  OpnameDaoManager(this._db);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$StockOpnamesTableTableManager get stockOpnames =>
      $$StockOpnamesTableTableManager(_db.attachedDatabase, _db.stockOpnames);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$StockOpnameItemsTableTableManager get stockOpnameItems =>
      $$StockOpnameItemsTableTableManager(
        _db.attachedDatabase,
        _db.stockOpnameItems,
      );
}
