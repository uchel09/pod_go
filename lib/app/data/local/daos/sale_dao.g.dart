// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_dao.dart';

// ignore_for_file: type=lint
mixin _$SaleDaoMixin on DatabaseAccessor<AppDatabase> {
  $RolesTable get roles => attachedDatabase.roles;
  $UsersTable get users => attachedDatabase.users;
  $SalesTable get sales => attachedDatabase.sales;
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $PaymentsTable get payments => attachedDatabase.payments;
  SaleDaoManager get managers => SaleDaoManager(this);
}

class SaleDaoManager {
  final _$SaleDaoMixin _db;
  SaleDaoManager(this._db);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db.attachedDatabase, _db.payments);
}
