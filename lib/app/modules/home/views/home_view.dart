import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/theme_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/adaptive_scaffold.dart';
import '../../../core/widgets/change_password_dialog.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../routes/app_pages.dart';
import '../controllers/home_controller.dart';
import '../../pos/views/pos_view.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    const destinations = [
      AdaptiveScaffoldDestination(
        label: 'Beranda',
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
      ),
      AdaptiveScaffoldDestination(
        label: 'Kasir',
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
      ),
      AdaptiveScaffoldDestination(
        label: 'Produk',
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
        actions: [
          IconButton(
            tooltip: 'Ganti Tema',
            icon: Icon(
              ThemeService.to.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
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
            _buildHomeTab(context),
            const PosView(),
            _buildProductsTab(context),
            const EmptyState(
              title: 'Laporan Penjualan',
              message: 'Modul laporan penjualan akan segera hadir.',
              icon: Icons.bar_chart_outlined,
            ),
            _buildSettingsTab(context),
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

  Widget _buildHomeTab(BuildContext context) {
    final store = AuthService.to.currentStore.value;
    final user = AuthService.to.currentUser.value;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              store?.name ?? 'Selamat Datang di $kAppName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              user != null ? 'Kasir: ${user.displayName}' : 'Mode Solo (Tanpa Login)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text('Uji Coba Currency Formatter:'),
                    const SizedBox(height: 8),
                    Text(
                      formatRupiah(1250000),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Device ID:\n${DeviceIdService.to.deviceId}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (PermissionService.to.can(PermissionKeys.posSell) ||
                PermissionService.to.can(PermissionKeys.posVoid)) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.history, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Riwayat Penjualan', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Lihat transaksi, cetak ulang struk, dan pembatalan (void)'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.SALES_HISTORY),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab(BuildContext context) {
    final theme = Theme.of(context);
    final canView = PermissionService.to.can(PermissionKeys.productView);

    if (!canView) {
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
                'Manajemen Produk',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Kelola kategori, satuan ukuran, dan katalog barang dagangan toko Anda.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              // Card Kategori
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
                    child: Icon(Icons.category_outlined, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Kategori Produk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('Kelola pengelompokan produk seperti Makanan, Minuman, Snack, dll.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.CATEGORIES),
                ),
              ),
              const SizedBox(height: 16),

              // Card Satuan
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
                    child: Icon(Icons.straighten_outlined, color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: const Text('Satuan Produk (Unit)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('Kelola satuan ukuran produk seperti pcs, kg, gram, liter, dus, dll.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.UNITS),
                ),
              ),
              const SizedBox(height: 16),

              // Card Katalog Produk
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
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('Katalog Produk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('Kelola data produk, harga jual/beli, stok, dan barcode barang toko Anda.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.PRODUCTS),
                ),
              ),
              const SizedBox(height: 16),

              // Card Cetak Label Barcode
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
                    child: Icon(Icons.qr_code_2, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Cetak Label Barcode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('Cetak stiker label barcode (Code128 / QR) produk dalam format PDF.'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.PRODUCT_LABELS),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context) {
    final store = AuthService.to.currentStore.value;
    final user = AuthService.to.currentUser.value;
    final requireLogin = AuthService.to.requireLogin;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pengaturan Aplikasi',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Info Toko & Pengguna Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.storefront),
                        title: Text(store?.name ?? 'Nama Toko'),
                        subtitle: Text('Mode: ${store?.mode.toUpperCase() ?? 'SOLO'} | Login: ${requireLogin ? 'Wajib' : 'Opsional (Nonaktif)'}'),
                      ),
                      if (user != null) ...[
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.account_circle_outlined),
                          title: Text(user.displayName),
                          subtitle: Text('@${user.username}'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              FilledButton.tonalIcon(
                onPressed: () => ThemeService.to.switchTheme(),
                icon: const Icon(Icons.brightness_6),
                label: const Text('Ganti Tema (Light / Dark)'),
              ),
              const SizedBox(height: 12),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Uji & Diagnostik Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tes scanner HID USB/Bluetooth dan kamera'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.SCANNER_TEST),
                ),
              ),
              const SizedBox(height: 12),

              if (PermissionService.to.can(PermissionKeys.settingsManage)) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('Printer Thermal & Struk', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Konfigurasi Bluetooth, USB Windows, LAN, atau PDF'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Get.toNamed(Routes.PRINTER_SETTINGS),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (user != null && requireLogin) ...[
                OutlinedButton.icon(
                  onPressed: () => ChangePasswordDialog.show(context),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Ganti Password / PIN'),
                ),
                const SizedBox(height: 12),
              ],

              // Tombol Logout hanya tampil bila requireLogin == true
              if (requireLogin)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => _handleLogout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar dari Akun Kasir'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
