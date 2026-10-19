import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/audit_dao.dart';
import 'daos/category_dao.dart';
import 'daos/license_dao.dart';
import 'daos/opname_dao.dart';
import 'daos/product_dao.dart';
import 'daos/purchase_dao.dart';
import 'daos/role_dao.dart';
import 'daos/sale_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/stock_dao.dart';
import 'daos/store_dao.dart';
import 'daos/supplier_dao.dart';
import 'daos/unit_dao.dart';
import 'daos/user_dao.dart';
import 'tables/app_settings.dart';
import 'tables/audit_logs.dart';
import 'tables/categories.dart';
import 'tables/licenses.dart';
import 'tables/payments.dart';
import 'tables/products.dart';
import 'tables/purchase_items.dart';
import 'tables/purchases.dart';
import 'tables/role_permissions.dart';
import 'tables/roles.dart';
import 'tables/sale_items.dart';
import 'tables/sales.dart';
import 'tables/stock_movements.dart';
import 'tables/stock_opname_items.dart';
import 'tables/stock_opnames.dart';
import 'tables/stores.dart';
import 'tables/suppliers.dart';
import 'tables/units.dart';
import 'tables/users.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Stores,
    Roles,
    RolePermissions,
    Users,
    Licenses,
    Categories,
    Units,
    Products,
    Suppliers,
    Sales,
    SaleItems,
    Payments,
    Purchases,
    PurchaseItems,
    StockMovements,
    StockOpnames,
    StockOpnameItems,
    AppSettings,
    AuditLogs,
  ],
  daos: [
    StoreDao,
    UserDao,
    RoleDao,
    ProductDao,
    CategoryDao,
    UnitDao,
    SupplierDao,
    SaleDao,
    PurchaseDao,
    StockDao,
    OpnameDao,
    SettingsDao,
    AuditDao,
    LicenseDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'pos_me'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS audit_logs_created_at_idx ON audit_logs (created_at);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS audit_logs_entity_idx ON audit_logs (entity, entity_id);',
          );
        }
      },
    );
  }
}

