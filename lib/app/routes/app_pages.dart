import 'package:get/get.dart';

import '../core/middleware/auth_middleware.dart';
import '../modules/categories/bindings/categories_binding.dart';
import '../modules/categories/views/categories_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/login/bindings/login_binding.dart';
import '../modules/login/views/login_view.dart';
import '../modules/pos/bindings/pos_binding.dart';
import '../modules/pos/views/pos_view.dart';
import '../modules/printer_settings/bindings/printer_settings_binding.dart';
import '../modules/printer_settings/views/printer_settings_view.dart';
import '../modules/product_labels/bindings/product_labels_binding.dart';
import '../modules/product_labels/views/product_labels_view.dart';
import '../modules/products/bindings/products_binding.dart';
import '../modules/products/views/products_view.dart';
import '../modules/sale_success/bindings/sale_success_binding.dart';
import '../modules/sale_success/views/sale_success_view.dart';
import '../modules/sales_history/bindings/sales_history_binding.dart';
import '../modules/sales_history/views/sales_history_view.dart';
import '../modules/scanner_test/bindings/scanner_test_binding.dart';
import '../modules/scanner_test/views/scanner_test_view.dart';
import '../modules/setup/bindings/setup_binding.dart';
import '../modules/setup/views/setup_view.dart';
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
  ];
}
