import 'package:get/get.dart';

import '../core/middleware/auth_middleware.dart';
import '../modules/activity_log/bindings/activity_log_binding.dart';
import '../modules/activity_log/views/activity_log_view.dart';
import '../modules/categories/bindings/categories_binding.dart';
import '../modules/categories/views/categories_view.dart';
import '../modules/dashboard/bindings/dashboard_binding.dart';
import '../modules/dashboard/views/dashboard_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/import_export/bindings/import_export_binding.dart';
import '../modules/import_export/views/import_export_view.dart';
import '../modules/import_wizard/bindings/import_wizard_binding.dart';
import '../modules/import_wizard/views/import_wizard_view.dart';
import '../modules/login/bindings/login_binding.dart';
import '../modules/login/views/login_view.dart';
import '../modules/opname_detail/bindings/opname_detail_binding.dart';
import '../modules/opname_detail/views/opname_detail_view.dart';
import '../modules/pos/bindings/pos_binding.dart';
import '../modules/pos/views/pos_view.dart';
import '../modules/printer_settings/bindings/printer_settings_binding.dart';
import '../modules/printer_settings/views/printer_settings_view.dart';
import '../modules/product_labels/bindings/product_labels_binding.dart';
import '../modules/product_labels/views/product_labels_view.dart';
import '../modules/products/bindings/products_binding.dart';
import '../modules/products/views/products_view.dart';
import '../modules/purchase_form/bindings/purchase_form_binding.dart';
import '../modules/purchase_form/views/purchase_form_view.dart';
import '../modules/purchases/bindings/purchases_binding.dart';
import '../modules/purchases/views/purchases_view.dart';
import '../modules/reports/bindings/reports_binding.dart';
import '../modules/reports/views/reports_view.dart';
import '../modules/sale_success/bindings/sale_success_binding.dart';
import '../modules/sale_success/views/sale_success_view.dart';
import '../modules/sales_history/bindings/sales_history_binding.dart';
import '../modules/sales_history/views/sales_history_view.dart';
import '../modules/scanner_test/bindings/scanner_test_binding.dart';
import '../modules/scanner_test/views/scanner_test_view.dart';
import '../modules/setup/bindings/setup_binding.dart';
import '../modules/setup/views/setup_view.dart';
import '../modules/stock_card/bindings/stock_card_binding.dart';
import '../modules/stock_card/views/stock_card_view.dart';
import '../modules/stock_opname/bindings/stock_opname_binding.dart';
import '../modules/stock_opname/views/stock_opname_view.dart';
import '../modules/suppliers/bindings/suppliers_binding.dart';
import '../modules/suppliers/views/suppliers_view.dart';
import '../modules/units/bindings/units_binding.dart';
import '../modules/units/views/units_view.dart';
import '../modules/upgrade/bindings/upgrade_binding.dart';
import '../modules/upgrade/views/upgrade_view.dart';

// ignore_for_file: constant_identifier_names

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.HOME;

  static final routes = [
    GetPage(
      name: _Paths.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.SETUP,
      page: () => const SetupView(),
      binding: SetupBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.LOGIN,
      page: () => const LoginView(),
      binding: LoginBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.UPGRADE,
      page: () => const UpgradeView(),
      binding: UpgradeBinding(),
    ),
    GetPage(
      name: _Paths.CATEGORIES,
      page: () => const CategoriesView(),
      binding: CategoriesBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.UNITS,
      page: () => const UnitsView(),
      binding: UnitsBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.PRODUCTS,
      page: () => const ProductsView(),
      binding: ProductsBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.SCANNER_TEST,
      page: () => const ScannerTestView(),
      binding: ScannerTestBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.PRODUCT_LABELS,
      page: () => const ProductLabelsView(),
      binding: ProductLabelsBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.POS,
      page: () => const PosView(),
      binding: PosBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.PRINTER_SETTINGS,
      page: () => const PrinterSettingsView(),
      binding: PrinterSettingsBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.SALE_SUCCESS,
      page: () => const SaleSuccessView(),
      binding: SaleSuccessBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.SALES_HISTORY,
      page: () => const SalesHistoryView(),
      binding: SalesHistoryBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.ACTIVITY_LOG,
      page: () => const ActivityLogView(),
      binding: ActivityLogBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.STOCK_CARD,
      page: () => const StockCardView(),
      binding: StockCardBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.SUPPLIERS,
      page: () => const SuppliersView(),
      binding: SuppliersBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.PURCHASES,
      page: () => const PurchasesView(),
      binding: PurchasesBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.PURCHASE_FORM,
      page: () => const PurchaseFormView(),
      binding: PurchaseFormBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.STOCK_OPNAME,
      page: () => const StockOpnameView(),
      binding: StockOpnameBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.OPNAME_DETAIL,
      page: () => const OpnameDetailView(),
      binding: OpnameDetailBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.DASHBOARD,
      page: () => const DashboardView(),
      binding: DashboardBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.REPORTS,
      page: () => const ReportsView(),
      binding: ReportsBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.IMPORT_EXPORT,
      page: () => const ImportExportView(),
      binding: ImportExportBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: _Paths.IMPORT_WIZARD,
      page: () => const ImportWizardView(),
      binding: ImportWizardBinding(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}
