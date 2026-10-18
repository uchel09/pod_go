// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stock_dao.dart';

// ignore_for_file: type=lint
mixin _$StockDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $RolesTable get roles => attachedDatabase.roles;
  $UsersTable get users => attachedDatabase.users;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;
  StockDaoManager get managers => StockDaoManager(this);
}

class StockDaoManager {
  final _$StockDaoMixin _db;
  StockDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.stockMovements,
      );
}
