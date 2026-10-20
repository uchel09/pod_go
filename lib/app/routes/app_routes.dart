// ignore_for_file: constant_identifier_names

part of 'app_pages.dart';

abstract class Routes {
  Routes._();
  static const SETUP = _Paths.SETUP;
  static const LOGIN = _Paths.LOGIN;
  static const HOME = _Paths.HOME;
  static const POS = _Paths.POS;
  static const PRODUCTS = _Paths.PRODUCTS;
  static const CATEGORIES = _Paths.CATEGORIES;
  static const UNITS = _Paths.UNITS;
  static const SALES_HISTORY = _Paths.SALES_HISTORY;
  static const PURCHASES = _Paths.PURCHASES;
  static const STOCK_OPNAME = _Paths.STOCK_OPNAME;
  static const REPORTS = _Paths.REPORTS;
  static const IMPORT_EXPORT = _Paths.IMPORT_EXPORT;
  static const BACKUP = _Paths.BACKUP;
  static const SETTINGS = _Paths.SETTINGS;
  static const UPGRADE = _Paths.UPGRADE;
  static const SCANNER_TEST = _Paths.SCANNER_TEST;
  static const PRODUCT_LABELS = _Paths.PRODUCT_LABELS;
  static const PRINTER_SETTINGS = _Paths.PRINTER_SETTINGS;
  static const SALE_SUCCESS = _Paths.SALE_SUCCESS;
  static const ACTIVITY_LOG = _Paths.ACTIVITY_LOG;
  static const STOCK_CARD = _Paths.STOCK_CARD;
  static const SUPPLIERS = _Paths.SUPPLIERS;
  static const PURCHASE_FORM = _Paths.PURCHASE_FORM;
  static const OPNAME_DETAIL = _Paths.OPNAME_DETAIL;
  static const DASHBOARD = _Paths.DASHBOARD;
  static const IMPORT_WIZARD = _Paths.IMPORT_WIZARD;
  static const CHECKOUT_SIMULATION = _Paths.CHECKOUT_SIMULATION;
  static const DEVELOPER_PANEL = _Paths.DEVELOPER_PANEL;
}

abstract class _Paths {
  _Paths._();
  static const SETUP = '/setup';
  static const LOGIN = '/login';
  static const HOME = '/home';
  static const POS = '/pos';
  static const PRODUCTS = '/products';
  static const CATEGORIES = '/categories';
  static const UNITS = '/units';
  static const SALES_HISTORY = '/sales-history';
  static const PURCHASES = '/purchases';
  static const STOCK_OPNAME = '/stock-opname';
  static const REPORTS = '/reports';
  static const IMPORT_EXPORT = '/import-export';
  static const BACKUP = '/backup';
  static const SETTINGS = '/settings';
  static const UPGRADE = '/upgrade';
  static const SCANNER_TEST = '/scanner-test';
  static const PRODUCT_LABELS = '/product-labels';
  static const PRINTER_SETTINGS = '/printer-settings';
  static const SALE_SUCCESS = '/sale-success';
  static const ACTIVITY_LOG = '/activity-log';
  static const STOCK_CARD = '/stock-card';
  static const SUPPLIERS = '/suppliers';
  static const PURCHASE_FORM = '/purchase-form';
  static const OPNAME_DETAIL = '/opname-detail';
  static const DASHBOARD = '/dashboard';
  static const IMPORT_WIZARD = '/import-wizard';
  static const CHECKOUT_SIMULATION = '/checkout-simulation';
  static const DEVELOPER_PANEL = '/developer-panel';
}
