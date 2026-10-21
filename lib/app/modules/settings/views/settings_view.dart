import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/tier_enum.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/theme_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../routes/app_pages.dart';
import '../../developer_panel/controllers/developer_panel_controller.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  final bool isEmbeddedInHome;

  const SettingsView({super.key, this.isEmbeddedInHome = false});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 750;
        return Obx(() {
          if (controller.isLoading.value && controller.storeNameController.text.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (isDesktop) {
            return _buildDesktopLayout(context);
          } else {
            return _buildMobileLayout(context);
          }
        });
      },
    );

    if (isEmbeddedInHome) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Get.back(),
              )
            : null,
      ),
      body: content,
    );
  }

  // ==========================================
  // DESKTOP TWO-PANEL LAYOUT
  // ==========================================

  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel Kiri: Daftar Menu Grup
        SizedBox(
          width: 280,
          child: Card(
            margin: const EdgeInsets.all(16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: _buildGroupMenuItems(context),
            ),
          ),
        ),

        // Panel Kanan: Konten Grup Terpilih
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _buildGroupContent(context, controller.selectedGroup.value),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MOBILE DRILL-DOWN LAYOUT
  // ==========================================

  Widget _buildMobileLayout(BuildContext context) {
    final theme = Theme.of(context);

    if (controller.isMobileDetailOpen.value) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            controller.isMobileDetailOpen.value = false;
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => controller.isMobileDetailOpen.value = false,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Kembali ke Menu Pengaturan'),
              ),
              const SizedBox(height: 16),
              _buildGroupContent(context, controller.selectedGroup.value),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'PILIH KATEGORI PENGATURAN',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ..._buildGroupCardsMobile(context),
      ],
    );
  }

  // ==========================================
  // MENU ITEMS & CARDS
  // ==========================================

  List<Widget> _buildGroupMenuItems(BuildContext context) {
    final groups = _getAvailableGroups();

    return groups.map((g) {
      final isSelected = controller.selectedGroup.value == g['id'];
      return ListTile(
        selected: isSelected,
        leading: Icon(g['icon'] as IconData),
        title: Text(
          g['title'] as String,
          style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
        ),
        onTap: () => controller.selectedGroup.value = g['id'] as int,
      );
    }).toList();
  }

  List<Widget> _buildGroupCardsMobile(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _getAvailableGroups();

    return groups.map((g) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            child: Icon(g['icon'] as IconData, color: theme.colorScheme.primary),
          ),
          title: Text(g['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(g['subtitle'] as String, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            controller.selectedGroup.value = g['id'] as int;
            controller.isMobileDetailOpen.value = true;
          },
        ),
      );
    }).toList();
  }

  List<Map<String, dynamic>> _getAvailableGroups() {
    final list = <Map<String, dynamic>>[];

    if (controller.canManageSettings) {
      list.add({
        'id': 0,
        'title': 'Profil Toko',
        'subtitle': 'Nama, alamat, telepon, dan footer struk',
        'icon': Icons.storefront,
      });
      list.add({
        'id': 1,
        'title': 'Penjualan & Struk',
        'subtitle': 'Stok minus, ambang diskon audit, dan lebar struk',
        'icon': Icons.point_of_sale,
      });
      list.add({
        'id': 9,
        'title': 'Pajak (PPN)',
        'subtitle': 'Atur tarif pajak, mode eksklusif atau inklusif',
        'icon': Icons.receipt_long,
      });
    }

    list.add({
      'id': 2,
      'title': 'Scanner Barcode',
      'subtitle': 'Format default 1D/2D dan tes scanner',
      'icon': Icons.qr_code_scanner,
    });

    list.add({
      'id': 3,
      'title': 'Printer Thermal',
      'subtitle': 'Konfigurasi Bluetooth, USB, LAN, atau PDF',
      'icon': Icons.print_outlined,
    });

    list.add({
      'id': 4,
      'title': 'Tampilan & Tema',
      'subtitle': 'Tema terang, gelap, sistem & warna utama',
      'icon': Icons.palette_outlined,
    });

    list.add({
      'id': 5,
      'title': 'Keamanan Akun',
      'subtitle': 'Ganti password/PIN, recovery code & proteksi login',
      'icon': Icons.lock_outline,
    });

    if (controller.canManageBackup) {
      list.add({
        'id': 6,
        'title': 'Pencadangan Data',
        'subtitle': 'Cadangkan & pulihkan database toko (ZIP)',
        'icon': Icons.backup_outlined,
      });
    }

    list.add({
      'id': 7,
      'title': 'Lisensi & Paket',
      'subtitle': 'Status tier aktif, masa berlaku & upgrade',
      'icon': Icons.workspace_premium_outlined,
    });

    list.add({
      'id': 8,
      'title': 'Tentang Aplikasi',
      'subtitle': 'Versi app, mode simulasi & mode developer',
      'icon': Icons.info_outline,
    });

    return list;
  }

  // ==========================================
  // DETAIL CONTENT DISPATCHER
  // ==========================================

  Widget _buildGroupContent(BuildContext context, int groupId) {
    switch (groupId) {
      case 0:
        return _buildStoreSection(context);
      case 1:
        return _buildSalesSection(context);
      case 2:
        return _buildScannerSection(context);
      case 3:
        return _buildPrinterSection(context);
      case 4:
        return _buildThemeSection(context);
      case 5:
        return _buildSecuritySection(context);
      case 6:
        return _buildBackupSection(context);
      case 7:
        return _buildLicenseSection(context);
      case 8:
        return _buildAboutSection(context);
      case 9:
        return _buildTaxSection(context);
      default:
        return _buildAboutSection(context);
    }
  }

  // ==========================================
  // GRUP 1: PROFIL TOKO
  // ==========================================

  Widget _buildStoreSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profil Toko & Struk',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Identitas ini dicetak pada bagian kepala (header) dan kaki (footer) struk belanja.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),
            TextField(
              controller: controller.storeNameController,
              decoration: const InputDecoration(
                labelText: 'Nama Toko *',
                hintText: 'Contoh: Toko Berkah Mandiri',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller.storeAddressController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alamat Toko',
                hintText: 'Jl. Raya No. 123, Kota',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller.storePhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor Telepon / WhatsApp',
                hintText: '081234567890',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller.receiptFooterController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan Kaki Struk (Footer)',
                hintText: 'Terima kasih atas kunjungan Anda!',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => controller.saveStoreProfile(),
              icon: const Icon(Icons.save),
              label: const Text('Simpan Profil Toko'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 2: PENJUALAN & STRUK
  // ==========================================

  Widget _buildSalesSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aturan Penjualan & Format Kasir',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Atur toleransi stok minus, ambang batas diskon audit, dan ukuran kertas struk.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            // Toggle Stok Minus
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Izinkan Stok Minus saat Transaksi',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Bila aktif, kasir dapat menyelesaikan transaksi walau stok tercatat 0 atau negatif.'),
                  value: controller.allowNegativeStock.value,
                  onChanged: (val) => controller.allowNegativeStock.value = val,
                )),
            const Divider(height: 24),

            // Ambang Diskon Audit
            TextField(
              controller: controller.discountThresholdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Ambang Diskon Audit (%)',
                hintText: 'Contoh: 10',
                border: OutlineInputBorder(),
                helperText: 'Pemberian diskon melebihi persentase ini akan dicatat ke audit log.',
                prefixIcon: Icon(Icons.percent),
              ),
            ),
            const SizedBox(height: 20),

            // Lebar Kertas Struk
            Text('Lebar Kertas Struk Bawaan',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Pengaturan ini otomatis disinkronkan dengan modul Pengaturan Printer.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Obx(() => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: '58',
                      label: Text('58 mm (32 Kolom)'),
                      icon: Icon(Icons.receipt),
                    ),
                    ButtonSegment(
                      value: '80',
                      label: Text('80 mm (48 Kolom)'),
                      icon: Icon(Icons.receipt_long),
                    ),
                  ],
                  selected: {controller.paperWidth.value},
                  onSelectionChanged: (val) {
                    if (val.isNotEmpty) controller.paperWidth.value = val.first;
                  },
                )),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: () => controller.saveSalesSettings(),
              icon: const Icon(Icons.save),
              label: const Text('Simpan Pengaturan Penjualan'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 9: PAJAK (PPN)
  // ==========================================

  Widget _buildTaxSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Pengaturan Pajak (PPN)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Atur pajak transaksi kasir. Nilai pajak dihitung konsisten pada kasir, struk belanja, dan laporan keuangan.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),

            // Toggle Aktifkan Pajak
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktifkan Pajak Transaksi',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Bila aktif, pajak akan otomatis dihitung saat checkout dan dicetak pada struk.'),
                  value: controller.taxEnabled.value,
                  onChanged: (val) => controller.taxEnabled.value = val,
                )),
            const SizedBox(height: 16),

            // Nama Pajak
            TextField(
              controller: controller.taxNameController,
              decoration: const InputDecoration(
                labelText: 'Nama Pajak',
                hintText: 'Contoh: PPN, PB1, Service Tax',
                border: OutlineInputBorder(),
                helperText: 'Nama yang akan tertera pada rincian kasir dan struk pembayaran.',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 20),

            // Tarif Pajak (%)
            TextField(
              controller: controller.taxRateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tarif Pajak (%)',
                hintText: 'Contoh: 11 atau 11.5',
                border: OutlineInputBorder(),
                helperText: 'Persentase tarif pajak (0% - 100%).',
                prefixIcon: Icon(Icons.percent),
              ),
            ),
            const SizedBox(height: 24),

            // Mode Pajak
            Text('Metode Perhitungan Pajak',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Obx(() => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'exclusive',
                      label: Text('Eksklusif (Ditambahkan)'),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                    ButtonSegment(
                      value: 'inclusive',
                      label: Text('Inklusif (Termasuk Harga)'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                  ],
                  selected: {controller.taxMode.value},
                  onSelectionChanged: (val) {
                    if (val.isNotEmpty) controller.taxMode.value = val.first;
                  },
                )),
            const SizedBox(height: 12),
            Obx(() {
              final isExclusive = controller.taxMode.value == 'exclusive';
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isExclusive ? Icons.info_outline : Icons.lightbulb_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isExclusive
                            ? 'Mode Eksklusif: Total = Subtotal + Pajak.\nContoh: Subtotal Rp 100.000 dengan tarif 11% menghasilkan Pajak Rp 11.000 (Total tagihan kasir Rp 111.000).'
                            : 'Mode Inklusif: Harga jual barang sudah termasuk pajak.\nContoh: Tagihan kasir Rp 111.000 dengan tarif 11% mengandung Pajak Rp 11.000 (Pendapatan bersih toko Rp 100.000).',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: () => controller.saveTaxSettings(),
              icon: const Icon(Icons.save),
              label: const Text('Simpan Pengaturan Pajak'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 3: SCANNER
  // ==========================================

  Widget _buildScannerSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pemindai Barcode & QR Code',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Atur tipe pemindai default toko dan jalankan diagnostik scanner.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            Text('Tipe Pemindai Default Toko',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Format cetak label barcode produk akan otomatis menyesuaikan opsi ini.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Obx(() => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: '1d',
                      label: Text('1D Barcode (Garis)'),
                      icon: Icon(Icons.view_week_outlined),
                    ),
                    ButtonSegment(
                      value: '2d',
                      label: Text('2D QR Code (Kotak)'),
                      icon: Icon(Icons.qr_code_2),
                    ),
                  ],
                  selected: {controller.scannerType.value},
                  onSelectionChanged: controller.canManageSettings
                      ? (val) {
                          if (val.isNotEmpty) controller.setScannerType(val.first);
                        }
                      : null,
                )),
            const Divider(height: 28),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.scanner)),
              title: const Text('Tes & Diagnostik Scanner',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Uji scanner fisik USB/Bluetooth atau kamera smartphone.'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Get.toNamed(Routes.SCANNER_TEST),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 4: PRINTER
  // ==========================================

  Widget _buildPrinterSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pencetak Struk (Printer Thermal)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Konfigurasi koneksi hardware printer Bluetooth, USB Windows, LAN, atau PDF.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            Obx(() => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Koneksi Printer Aktif:',
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            controller.printerType.value.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Target Perangkat:', style: TextStyle(color: Colors.grey)),
                          Text(
                            controller.printerTarget.value.isNotEmpty
                                ? controller.printerTarget.value
                                : 'PDF Virtual / Belum Dipilih',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mode Cetak Transaksi:',
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            controller.receiptModeLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 20),

            FilledButton.tonalIcon(
              onPressed: () => Get.toNamed(Routes.PRINTER_SETTINGS),
              icon: const Icon(Icons.settings_suggest_outlined),
              label: const Text('Buka Pengaturan Printer Lengkap'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 5: TAMPILAN & TEMA
  // ==========================================

  Widget _buildThemeSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tampilan & Tema Aplikasi',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Sesuaikan mode pencahayaan dan warna aksen antarmuka.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            Text('Mode Tema',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistem'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Terang'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Gelap'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {controller.currentThemeMode},
              onSelectionChanged: (val) {
                if (val.isNotEmpty) controller.setThemeMode(val.first);
              },
            ),
            const SizedBox(height: 24),

            Text('Warna Aksen Utama',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ThemeService.availableColors.map((item) {
                final color = item['color'] as Color;
                final name = item['name'] as String;
                final isSelected = controller.currentPrimaryColor.toARGB32() == color.toARGB32();

                return InkWell(
                  onTap: () => controller.setPrimaryColor(color),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.15) : null,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? color : theme.colorScheme.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 8, backgroundColor: color),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? color : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 6: KEAMANAN AKUN
  // ==========================================

  Widget _buildSecuritySection(BuildContext context) {
    final theme = Theme.of(context);
    final user = controller.currentUser.value;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Keamanan Akun & Kredensial',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Kelola kredensial masuk kasir, PIN, dan kode pemulihan akun.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            if (user != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('@${user.username}'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showChangePasswordDialog(context),
                icon: const Icon(Icons.password),
                label: const Text('Ganti Password / PIN Kasir'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _showRotateRecoveryCodeDialog(context),
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('Buat / Perbarui Recovery Code 16 Karakter'),
              ),
              const Divider(height: 28),
            ],

            // Khusus Mode Solo: Opsi Aktifkan / Nonaktifkan Login Wajib
            if (controller.isSoloMode && controller.canManageSettings) ...[
              Text('Mode Penguncian Toko (Mode Solo)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Mengaktifkan login mewajibkan memasukkan PIN/Password saat membuka aplikasi. Mematikan login memungkinkan kasir langsung masuk tanpa password.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Obx(() {
                final isReq = controller.requireLogin;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isReq ? Colors.green.shade100 : Colors.amber.shade100,
                    child: Icon(
                      isReq ? Icons.lock : Icons.lock_open,
                      color: isReq ? Colors.green.shade800 : Colors.amber.shade900,
                    ),
                  ),
                  title: Text(
                    isReq ? 'Login Wajib Aktif' : 'Login Dinonaktifkan (Langsung Masuk)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(isReq
                      ? 'Aplikasi terkunci password/PIN saat dibuka.'
                      : 'Aplikasi langsung terbuka tanpa meminta kredensial.'),
                  trailing: FilledButton.tonal(
                    onPressed: () {
                      if (isReq) {
                        _showDeactivateLoginDialog(context);
                      } else {
                        _showActivateLoginDialog(context);
                      }
                    },
                    child: Text(isReq ? 'Nonaktifkan' : 'Aktifkan'),
                  ),
                );
              }),
              const Divider(height: 28),
            ],

            if (controller.requireLogin)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Keluar dari Akun Kasir'),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 7: BACKUP
  // ==========================================

  Widget _buildBackupSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pencadangan Database Toko (Backup)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Simpan seluruh database toko ke berkas ZIP atau pulihkan dari cadangan.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            Obx(() => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Backup Terakhir:',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(
                              controller.lastBackupInfo.value,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 20),

            FilledButton.tonalIcon(
              onPressed: () => Get.toNamed(Routes.BACKUP),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Buka Menu Backup & Restore Lengkap'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 8: LISENSI & PAKET
  // ==========================================

  Widget _buildLicenseSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lisensi & Paket Fitur Aplikasi',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Periksa tier aktif, batasan produk, dan masa berlaku langganan toko.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            Obx(() {
              final tier = controller.currentTier.value;
              final expires = controller.activeLicenseExpiresAt.value;
              final expireText = expires != null
                  ? DateFormat('dd MMMM yyyy, HH:mm').format(expires)
                  : 'Permanen / Tanpa Batas Waktu';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tier == Tier.premium
                      ? Colors.purple.shade50
                      : (tier == Tier.semi ? Colors.blue.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: tier == Tier.premium
                        ? Colors.purple.shade200
                        : (tier == Tier.semi ? Colors.blue.shade200 : Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Paket Lisensi Aktif:'),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tier == Tier.premium
                                ? Colors.purple.shade600
                                : (tier == Tier.semi ? Colors.blue.shade700 : Colors.grey.shade700),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tier.displayName,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Masa Berlaku:'),
                        Text(expireText, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: () => Get.toNamed(Routes.UPGRADE),
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Upgrade / Kelola Paket'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GRUP 9: TENTANG APLIKASI
  // ==========================================

  Widget _buildAboutSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tentang Aplikasi POS Me',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Informasi versi build, sistem operasi, dan hak pengembang.',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),

            // Versi Aplikasi dengan 7-tap detector
            InkWell(
              onTap: () => DeveloperPanelController.registerVersionTap(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.info, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POS Me UMKM',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Obx(() => Text(
                                'Versi ${controller.appVersion.value}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                          if (controller.isSimulationMode)
                            Text(
                              'Mode Simulasi Aktif (Ketuk 7x untuk Developer)',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Obx(() {
              if (!controller.isDevModeAllowed) return const SizedBox.shrink();

              return Card(
                elevation: 0,
                color: Colors.amber.shade50.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.amber.shade400),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: Icon(Icons.developer_mode, color: Colors.amber.shade900),
                  ),
                  title: const Text('Panel Developer Simulasi',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Uji instan tier, transaksi gagal, kedaluwarsa & data dummy'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.toNamed(Routes.DEVELOPER_PANEL),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DIALOGS KEAMANAN
  // ==========================================

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Ganti Password / PIN Kasir'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password / PIN Lama *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Password / PIN Baru *',
                    hintText: 'Min. 4 karakter atau digit PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Ulangi Password / PIN Baru *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await controller.changePassword(
                    oldSecret: oldController.text,
                    newSecret: newController.text,
                    confirmSecret: confirmController.text,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  Get.snackbar(
                    'Berhasil',
                    'Password / PIN kasir berhasil diperbarui.',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.green.shade800,
                    colorText: Colors.white,
                  );
                } catch (e) {
                  Get.snackbar(
                    'Gagal',
                    e.toString(),
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.red.shade800,
                    colorText: Colors.white,
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRotateRecoveryCodeDialog(BuildContext context) async {
    final code = controller.generateRecoveryCode();
    bool isConfirmed = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Recovery Code Baru'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Gunakan kode pemulihan ini jika Anda lupa password/PIN. '
                  'Kode ini HANYA DITAMPILKAN SEKALI:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Salin Kode',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          Get.snackbar(
                            'Disalin',
                            'Recovery code berhasil disalin ke clipboard.',
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.grey.shade900,
                            colorText: Colors.white,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isConfirmed,
                  onChanged: (val) => setState(() => isConfirmed = val ?? false),
                  title: const Text(
                    'Sudah saya catat atau simpan di tempat aman.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: isConfirmed
                  ? () async {
                      try {
                        await controller.saveRotatedRecoveryCode(code);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        Get.snackbar(
                          'Berhasil',
                          'Recovery Code baru telah disimpan.',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.green.shade800,
                          colorText: Colors.white,
                        );
                      } catch (e) {
                        Get.snackbar(
                          'Gagal',
                          e.toString(),
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.red.shade800,
                          colorText: Colors.white,
                        );
                      }
                    }
                  : null,
              child: const Text('Terapkan & Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActivateLoginDialog(BuildContext context) async {
    final secretController = TextEditingController();
    final confirmController = TextEditingController();
    final recoveryCode = controller.generateRecoveryCode();
    bool isCodeConfirmed = false;
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Aktifkan Login Wajib'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Untuk mengaktifkan login, buat password/PIN baru dan simpan Recovery Code berikut:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: secretController,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password / PIN Baru *',
                      hintText: 'Min. 4 karakter',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmController,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Ulangi Password / PIN *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recovery Code Pemulihan:',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              recoveryCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: 'Salin Kode',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: recoveryCode));
                                Get.snackbar(
                                  'Disalin',
                                  'Recovery Code berhasil disalin.',
                                  snackPosition: SnackPosition.BOTTOM,
                                  backgroundColor: Colors.grey.shade900,
                                  colorText: Colors.white,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isCodeConfirmed,
                    onChanged: (val) => setState(() => isCodeConfirmed = val ?? false),
                    title: const Text(
                      'Sudah saya catat Recovery Code ini.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: isCodeConfirmed
                  ? () async {
                      if (secretController.text != confirmController.text) {
                        Get.snackbar('Gagal', 'Konfirmasi password tidak cocok.');
                        return;
                      }
                      try {
                        await controller.activateSoloLogin(
                          newSecret: secretController.text,
                          newRecoveryCode: recoveryCode,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        Get.snackbar(
                          'Login Diaktifkan',
                          'Mode login wajib berhasil diaktifkan.',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.green.shade800,
                          colorText: Colors.white,
                        );
                      } catch (e) {
                        Get.snackbar('Gagal Mengaktifkan Login', e.toString());
                      }
                    }
                  : null,
              child: const Text('Aktifkan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeactivateLoginDialog(BuildContext context) async {
    final verifyController = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nonaktifkan Login Wajib?'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Masukkan password/PIN saat ini untuk mengonfirmasi penonaktifan login:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: verifyController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password / PIN Saat Ini *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade900),
              onPressed: () async {
                try {
                  await controller.deactivateSoloLogin(verifyController.text);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  Get.snackbar(
                    'Login Dinonaktifkan',
                    'Sistem tidak lagi meminta password saat dibuka.',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.blue.shade800,
                    colorText: Colors.white,
                  );
                } catch (e) {
                  Get.snackbar('Gagal Menonaktifkan Login', e.toString());
                }
              },
              child: const Text('Konfirmasi & Nonaktifkan'),
            ),
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
      Get.find<AuthService>().logout();
      Get.offAllNamed(Routes.LOGIN);
    }
  }
}
