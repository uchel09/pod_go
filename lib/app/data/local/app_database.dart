import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/audit_dao.dart';
import 'daos/category_dao.dart';
import 'daos/customer_dao.dart';
import 'daos/expense_dao.dart';
import 'daos/license_dao.dart';
import 'daos/opname_dao.dart';
import 'daos/product_dao.dart';
import 'daos/purchase_dao.dart';
import 'daos/role_dao.dart';
import 'daos/sale_dao.dart';
import 'daos/sale_return_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/stock_dao.dart';
import 'daos/store_dao.dart';
import 'daos/supplier_dao.dart';
import 'daos/unit_dao.dart';
import 'daos/user_dao.dart';
import 'tables/app_settings.dart';
import 'tables/audit_logs.dart';
import 'tables/categories.dart';
import 'tables/customer_payments.dart';
import 'tables/customers.dart';
import 'tables/expense_categories.dart';
import 'tables/expenses.dart';
import 'tables/licenses.dart';
import 'tables/payments.dart';
import 'tables/products.dart';
import 'tables/purchase_items.dart';
import 'tables/purchases.dart';
import 'tables/role_permissions.dart';
import 'tables/roles.dart';
import 'tables/sale_items.dart';
import 'tables/sale_return_items.dart';
import 'tables/sale_returns.dart';
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
    SaleReturns,
    SaleReturnItems,
    Payments,
    Purchases,
    PurchaseItems,
    StockMovements,
    StockOpnames,
    StockOpnameItems,
    AppSettings,
    AuditLogs,
    ExpenseCategories,
    Expenses,
    Customers,
    CustomerPayments,
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
    SaleReturnDao,
    PurchaseDao,
    StockDao,
    OpnameDao,
    SettingsDao,
    AuditDao,
    LicenseDao,
    ExpenseDao,
    CustomerDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'pos_me'));

  @override
  int get schemaVersion => 7;

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
        if (from < 3) {
          await m.addColumn(sales, sales.taxRateBps);
          await m.addColumn(sales, sales.taxMode);
        }
        if (from < 4) {
          await m.createTable(saleReturns);
          await m.createTable(saleReturnItems);
        }
        if (from < 5) {
          await m.createTable(expenseCategories);
          await m.createTable(expenses);
        }
        if (from < 6) {
          await m.createTable(customers);
          await m.createTable(customerPayments);
          await m.addColumn(sales, sales.customerId);
          await m.addColumn(saleReturns, saleReturns.creditRefund);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS customers_name_idx ON customers (name);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS customers_phone_idx ON customers (phone);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS customer_payments_customer_id_idx ON customer_payments (customer_id);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS customer_payments_created_at_idx ON customer_payments (created_at);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS sales_customer_id_idx ON sales (customer_id);',
          );
        }
        if (from < 7) {
          await m.addColumn(saleItems, saleItems.discountShare);
        }
      },
      beforeOpen: (details) async {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items (sale_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items (product_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale_id ON sale_returns (sale_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sale_return_items_return_id ON sale_return_items (return_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON stock_movements (product_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at ON stock_movements (created_at);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_status_created_at ON sales (status, created_at);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_date_status ON expenses (date, status);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_category_id ON expenses (category_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_customer_payments_customer_id ON customer_payments (customer_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON sales (customer_id);',
        );
        await expenseDao.seedDefaultCategories();
      },
    );
  }
}

