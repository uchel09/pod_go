/// Daftar konstanta kunci hak akses (permissions) dalam sistem POS Me.
abstract class PermissionKeys {
  PermissionKeys._();

  // POS
  static const posSell = 'pos.sell';
  static const posDiscount = 'pos.discount';
  static const posVoid = 'pos.void';

  // Product
  static const productView = 'product.view';
  static const productEdit = 'product.edit';
  static const productEditPrice = 'product.edit_price';
  static const productViewCost = 'product.view_cost';

  // Stock
  static const stockView = 'stock.view';
  static const stockAdjust = 'stock.adjust';
  static const stockPurchase = 'stock.purchase';
  static const stockOpname = 'stock.opname';

  // Report
  static const reportViewBasic = 'report.view_basic';
  static const reportViewProfit = 'report.view_profit';
  static const reportExport = 'report.export';

  // Import / Export
  static const importManage = 'import.manage';

  // Backup
  static const backupManage = 'backup.manage';

  // Settings & License
  static const settingsManage = 'settings.manage';
  static const licenseManage = 'license.manage';

  // Employee, Attendance, Role & Audit
  static const employeeManage = 'employee.manage';
  static const attendanceSelf = 'attendance.self';
  static const roleManage = 'role.manage';
  static const auditView = 'audit.view';

  /// Semua daftar kunci permission yang valid
  static const List<String> all = [
    posSell,
    posDiscount,
    posVoid,
    productView,
    productEdit,
    productEditPrice,
    productViewCost,
    stockView,
    stockAdjust,
    stockPurchase,
    stockOpname,
    reportViewBasic,
    reportViewProfit,
    reportExport,
    importManage,
    backupManage,
    settingsManage,
    licenseManage,
    employeeManage,
    attendanceSelf,
    roleManage,
    auditView,
  ];
}

