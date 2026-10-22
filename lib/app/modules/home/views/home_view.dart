import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_config.dart';
import '../../../core/features/feature_enum.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/theme/theme_service.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/adaptive_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_state.dart';
import '../../../routes/app_pages.dart';
import '../../dashboard/views/dashboard_view.dart';
import '../../reports/views/reports_view.dart';
import '../../settings/views/settings_view.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    const destinations = [
      AdaptiveScaffoldDestination(
        label: 'Dashboard',
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
      ),
      AdaptiveScaffoldDestination(
        label: 'Penjualan',
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
      ),
      AdaptiveScaffoldDestination(
        label: 'Produk & Stok',
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
      ),
      AdaptiveScaffoldDestination(
        label: 'Laporan',
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
      ),
      AdaptiveScaffoldDestination(
        label: 'Pengaturan',
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
      ),
    ];

    return Obx(
      () => AdaptiveScaffold(
        title: AuthService.to.currentStore.value?.name ?? kAppName,
        currentIndex: controller.selectedIndex.value,
        onDestinationSelected: controller.changeTabIndex,
        destinations: destinations,
        railTrailing: Obx(() {
          final hasPurchases = FeatureGate.to.isEnabled(Feature.purchases);
          final hasOpname = FeatureGate.to.isEnabled(Feature.stockOpname);
          final hasExpenses = FeatureGate.to.isEnabled(Feature.expenses);
          final hasCustomers = FeatureGate.to.isEnabled(Feature.customerCredit);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: hasCustomers ? 'Pelanggan & Kasbon' : 'Pelanggan (Perlu Semi-Premium)',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.people_outline),
                    if (!hasCustomers)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  if (hasCustomers) {
                    Get.toNamed(Routes.CUSTOMERS);
                  } else {
                    FeatureGate.to.requireFeature(Feature.customerCredit);
                  }
                },
              ),
              IconButton(
                tooltip: hasExpenses ? 'Pengeluaran Operasional' : 'Pengeluaran (Perlu Semi-Premium)',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.request_quote_outlined),
                    if (!hasExpenses)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  if (hasExpenses) {
                    Get.toNamed(Routes.EXPENSES);
                  } else {
                    FeatureGate.to.requireFeature(Feature.expenses);
                  }
                },
              ),
              IconButton(
                tooltip: hasOpname ? 'Stock Opname' : 'Stock Opname (Perlu Semi-Premium)',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.checklist_rtl_outlined),
                    if (!hasOpname)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  if (hasOpname) {
                    Get.toNamed(Routes.STOCK_OPNAME);
                  } else {
                    FeatureGate.to.requireFeature(Feature.stockOpname);
                  }
                },
              ),
              IconButton(
                tooltip: hasPurchases ? 'Pembelian Barang' : 'Pembelian (Perlu Semi-Premium)',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.local_shipping_outlined),
                    if (!hasPurchases)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  if (hasPurchases) {
                    Get.toNamed(Routes.PURCHASES);
                  } else {
                    FeatureGate.to.requireFeature(Feature.purchases);
                  }
                },
              ),
              IconButton(
                tooltip: hasPurchases ? 'Data Supplier' : 'Supplier (Perlu Semi-Premium)',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.business_outlined),
                    if (!hasPurchases)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  if (hasPurchases) {
                    Get.toNamed(Routes.SUPPLIERS);
                  } else {
                    FeatureGate.to.requireFeature(Feature.purchases);
                  }
                },
              ),
            ],
          );
        }),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Fitur Ekstra',
            icon: Obx(() {
              final hasPurchases = FeatureGate.to.isEnabled(Feature.purchases);
              final hasOpname = FeatureGate.to.isEnabled(Feature.stockOpname);
              final allUnlocked = hasPurchases && hasOpname;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.inventory_outlined),
                  if (!allUnlocked)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock, size: 10, color: Colors.black87),
                      ),
                    ),
                ],
              );
            }),
            onSelected: (val) {
              final hasPurchases = FeatureGate.to.isEnabled(Feature.purchases);
              final hasOpname = FeatureGate.to.isEnabled(Feature.stockOpname);
              final hasExpenses = FeatureGate.to.isEnabled(Feature.expenses);
              final hasCustomers = FeatureGate.to.isEnabled(Feature.customerCredit);
              if (val == 'customers') {
                if (hasCustomers) {
                  Get.toNamed(Routes.CUSTOMERS);
                } else {
                  FeatureGate.to.requireFeature(Feature.customerCredit);
                }
              } else if (val == 'expenses') {
                if (hasExpenses) {
                  Get.toNamed(Routes.EXPENSES);
                } else {
                  FeatureGate.to.requireFeature(Feature.expenses);
                }
              } else if (val == 'opname') {
                if (hasOpname) {
                  Get.toNamed(Routes.STOCK_OPNAME);
                } else {
                  FeatureGate.to.requireFeature(Feature.stockOpname);
                }
              } else if (val == 'purchases') {
                if (hasPurchases) {
                  Get.toNamed(Routes.PURCHASES);
                } else {
                  FeatureGate.to.requireFeature(Feature.purchases);
                }
              } else if (val == 'suppliers') {
                if (hasPurchases) {
                  Get.toNamed(Routes.SUPPLIERS);
                } else {
                  FeatureGate.to.requireFeature(Feature.purchases);
                }
              } else if (val == 'import_export') {
                if (FeatureGate.to.isEnabled(Feature.importExport)) {
                  Get.toNamed(Routes.IMPORT_EXPORT);
                } else {
                  FeatureGate.to.requireFeature(Feature.importExport);
                }
              } else if (val == 'backup') {
                Get.toNamed(Routes.BACKUP);
              }
            },
            itemBuilder: (context) {
              final hasPurchases = FeatureGate.to.isEnabled(Feature.purchases);
              final hasOpname = FeatureGate.to.isEnabled(Feature.stockOpname);
              final hasExpenses = FeatureGate.to.isEnabled(Feature.expenses);
              final hasCustomers = FeatureGate.to.isEnabled(Feature.customerCredit);
              final hasImportExport = FeatureGate.to.isEnabled(Feature.importExport);
              final canBackup = PermissionService.to.can(PermissionKeys.backupManage);
              return [
                PopupMenuItem(
                  value: 'customers',
                  child: Row(
                    children: [
                      const Icon(Icons.people_outline, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Pelanggan & Kasbon')),
                      if (!hasCustomers) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'expenses',
                  child: Row(
                    children: [
                      const Icon(Icons.request_quote_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Pengeluaran Operasional')),
                      if (!hasExpenses) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'opname',
                  child: Row(
                    children: [
                      const Icon(Icons.checklist_rtl_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Stock Opname')),
                      if (!hasOpname) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'purchases',
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Pembelian Barang')),
                      if (!hasPurchases) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'suppliers',
                  child: Row(
                    children: [
                      const Icon(Icons.business_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Data Supplier')),
                      if (!hasPurchases) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'import_export',
                  child: Row(
                    children: [
                      const Icon(Icons.sync_alt, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Import & Export Data')),
                      if (!hasImportExport) const Icon(Icons.lock, size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                if (canBackup)
                  const PopupMenuItem(
                    value: 'backup',
                    child: Row(
                      children: [
                        Icon(Icons.backup_outlined, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Backup Data')),
                      ],
                    ),
                  ),
              ];
            },
          ),
          IconButton(
            tooltip: 'Ganti Tema',
            icon: Icon(
              ThemeService.to.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: () => ThemeService.to.switchTheme(),
          ),
          if (AuthService.to.requireLogin)
            IconButton(
              tooltip: 'Keluar (Logout)',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => _handleLogout(context),
            ),
        ],
        body: IndexedStack(
          index: controller.selectedIndex.value,
          children: [
            const DashboardView(),
            _buildSalesTab(context),
            _buildProductsTab(context),
            const ReportsView(),
            const SettingsView(isEmbeddedInHome: true),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await ConfirmDialog.show(
      context: context,
      title: 'Konfirmasi Keluar',
      message: 'Apakah Anda yakin ingin keluar dari akun kasir?',
      confirmText: 'Keluar',
      isDestructive: true,
    );

    if (confirm) {
      AuthService.to.logout();
      Get.offAllNamed(Routes.LOGIN);
    }
  }

  /// Tab 1: Menu Penjualan & Kasir
  Widget _buildSalesTab(BuildContext context) {
    final theme = Theme.of(context);
    final canSell = PermissionService.to.can(PermissionKeys.posSell);
    final canViewHistory = PermissionService.to.can(PermissionKeys.posSell) ||
        PermissionService.to.can(PermissionKeys.posVoid);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Menu Penjualan',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Operasional transaksi kasir langsung, cetak struk, dan riwayat pesanan.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (canSell) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.point_of_sale, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    title: const Text('Buka Kasir (POS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: const Text('Lakukan checkout penjualan, pemindaian barcode, diskon, dan pembayaran kasir.'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Get.toNamed(Routes.POS),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (canViewHistory) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.history, color: theme.colorScheme.onSecondaryContainer),
                    ),
                    title: const Text('Riwayat Penjualan & Void', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: const Text('Daftar transaksi harian, filter status, cetak ulang struk, dan pembatalan transaksi.'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Get.toNamed(Routes.SALES_HISTORY),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.red.shade50,
                    child: Icon(Icons.request_quote_outlined, color: Colors.red.shade800),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Pengeluaran Operasional', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Obx(() {
                        final hasExpenses = FeatureGate.to.isEnabled(Feature.expenses);
                        if (!hasExpenses) {
                          return const Icon(Icons.lock, size: 16, color: Colors.amber);
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                  ),
                  subtitle: const Text('Catat biaya sewa, listrik, air, gaji, kemasan, dan biaya operasional lainnya.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.expenses)) {
                      Get.toNamed(Routes.EXPENSES);
                    } else {
                      FeatureGate.to.requireFeature(Feature.expenses);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.indigo.shade50,
                    child: Icon(Icons.people_outline, color: Colors.indigo.shade800),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Pelanggan & Kasbon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Obx(() {
                        final hasCust = FeatureGate.to.isEnabled(Feature.customerCredit);
                        if (!hasCust) {
                          return const Icon(Icons.lock, size: 16, color: Colors.amber);
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                  ),
                  subtitle: const Text('Kelola data pelanggan, pantau hutang/kasbon, dan terima pelunasan.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.customerCredit)) {
                      Get.toNamed(Routes.CUSTOMERS);
                    } else {
                      FeatureGate.to.requireFeature(Feature.customerCredit);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab 2: Menu Produk & Manajemen Stok
  Widget _buildProductsTab(BuildContext context) {
    final theme = Theme.of(context);
    final canViewProduct = PermissionService.to.can(PermissionKeys.productView);

    if (!canViewProduct) {
      return const ErrorState(
        title: 'Akses Ditolak',
        message: 'Anda tidak memiliki hak akses untuk melihat menu produk.',
        icon: Icons.lock_outline,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Produk & Stok',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Kelola master barang dagangan, kategori, satuan, serta alur stok toko.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              // Kelompok 1: Katalog & Master Produk
              Text(
                'KATALOG & MASTER PRODUK',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Katalog Produk', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Daftar barang dagangan, harga jual, harga beli, dan barcode'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.PRODUCTS),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(Icons.category_outlined, color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: const Text('Kategori Produk', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pengelompokan barang (Makanan, Minuman, Sembako, dll.)'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.CATEGORIES),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.straighten_outlined, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('Satuan Ukuran (Unit)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Satuan barang (pcs, kg, gram, liter, pack, botol, dll.)'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.UNITS),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.qr_code_2, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Cetak Label Barcode', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Cetak stiker barcode (Code128 / QR) dalam format PDF'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.PRODUCT_LABELS),
                ),
              ),

              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.sync_alt, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Import & Export Data', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Obx(() {
                        final hasImportExport = FeatureGate.to.isEnabled(Feature.importExport);
                        if (!hasImportExport) {
                          return const Icon(Icons.lock, size: 16, color: Colors.amber);
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                  ),
                  subtitle: const Text('Impor & ekspor massal produk, kategori, dan supplier via CSV/Excel'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.importExport)) {
                      Get.toNamed(Routes.IMPORT_EXPORT);
                    } else {
                      FeatureGate.to.requireFeature(Feature.importExport);
                    }
                  },
                ),
              ),

              const SizedBox(height: 24),
              // Kelompok 2: Manajemen Stok & Inventaris
              Text(
                'MANAJEMEN STOK & INVENTARIS',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              if (PermissionService.to.can(PermissionKeys.stockView)) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.table_chart_outlined, color: theme.colorScheme.onSecondaryContainer),
                    ),
                    title: const Text('Kartu Stok', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Lacak riwayat mutasi masuk/keluar dan saldo berjalan stok'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Get.toNamed(Routes.STOCK_CARD),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Card Stock Opname
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.checklist_rtl_outlined, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Stock Opname', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (!FeatureGate.to.isEnabled(Feature.stockOpname)) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.lock, size: 16, color: Colors.amber),
                      ],
                    ],
                  ),
                  subtitle: const Text('Pencocokan stok fisik berkala dengan sistem untuk mencegah selisih'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.stockOpname)) {
                      Get.toNamed(Routes.STOCK_OPNAME);
                    } else {
                      FeatureGate.to.requireFeature(Feature.stockOpname);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Card Pembelian Barang
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.local_shipping_outlined, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Pembelian & Penerimaan Barang', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (!FeatureGate.to.isEnabled(Feature.purchases)) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.lock, size: 16, color: Colors.amber),
                      ],
                    ],
                  ),
                  subtitle: const Text('Catat faktur masuk supplier dan tambah stok barang secara otomatis'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.purchases)) {
                      Get.toNamed(Routes.PURCHASES);
                    } else {
                      FeatureGate.to.requireFeature(Feature.purchases);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Card Supplier
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(Icons.business_outlined, color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text('Data Supplier', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (!FeatureGate.to.isEnabled(Feature.purchases)) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.lock, size: 16, color: Colors.amber),
                      ],
                    ],
                  ),
                  subtitle: const Text('Kelola kontak dan alamat distributor / pemasok barang toko'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (FeatureGate.to.isEnabled(Feature.purchases)) {
                      Get.toNamed(Routes.SUPPLIERS);
                    } else {
                      FeatureGate.to.requireFeature(Feature.purchases);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
