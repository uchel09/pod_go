import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/export_models.dart';
import '../../../data/services/import_template_service.dart';
import '../controllers/import_export_controller.dart';

class ImportExportView extends GetView<ImportExportController> {
  const ImportExportView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import & Export Data'),
        centerTitle: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Banner
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(Icons.sync_alt, color: theme.colorScheme.onPrimary, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Migrasi, Impor & Ekspor Data',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Kelola data massal dengan mudah. Impor produk, kategori, dan pemasok menggunakan template resmi, atau ekspor data transaksi dan pembukuan ke format CSV dan Excel.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // =============================================================
                // SECTION 1: IMPORT DATA
                // =============================================================
                Text(
                  'IMPORT DATA',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),

                // Card Produk
                _buildImportCard(
                  context: context,
                  title: 'Katalog Produk',
                  subtitle: 'Nama, barcode, SKU, kategori, satuan, harga jual, harga beli, stok awal, dan stok minimum.',
                  icon: Icons.inventory_2_outlined,
                  iconBgColor: theme.colorScheme.primaryContainer,
                  iconColor: theme.colorScheme.onPrimaryContainer,
                  type: ImportTemplateType.product,
                ),
                const SizedBox(height: 16),

                // Card Kategori
                _buildImportCard(
                  context: context,
                  title: 'Kategori Produk',
                  subtitle: 'Daftar pengelompokan barang (Makanan, Minuman, Sembako, dll.).',
                  icon: Icons.category_outlined,
                  iconBgColor: theme.colorScheme.secondaryContainer,
                  iconColor: theme.colorScheme.onSecondaryContainer,
                  type: ImportTemplateType.category,
                ),
                const SizedBox(height: 16),

                // Card Supplier
                _buildImportCard(
                  context: context,
                  title: 'Data Supplier / Pemasok',
                  subtitle: 'Daftar mitra pemasok barang, kontak telepon, dan alamat usaha.',
                  icon: Icons.business_outlined,
                  iconBgColor: theme.colorScheme.tertiaryContainer,
                  iconColor: theme.colorScheme.onTertiaryContainer,
                  type: ImportTemplateType.supplier,
                ),
                const SizedBox(height: 36),

                // =============================================================
                // SECTION 2: EXPORT DATA (PROMPT 14B)
                // =============================================================
                Text(
                  'EXPORT DATA (CSV & EXCEL)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),

                // 1. Ekspor Produk
                _buildExportCard(
                  context: context,
                  title: 'Katalog Produk Lengkap',
                  subtitle: 'Daftar semua produk aktif/nonaktif, kode internal, barcode, SKU, kategori, satuan, stok, harga jual, dan harga beli (bila berizin).',
                  icon: Icons.inventory_outlined,
                  iconBgColor: Colors.blue.shade100,
                  iconColor: Colors.blue.shade800,
                  actions: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => controller.exportProducts(ExportFormat.csv),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('Ekspor CSV'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => controller.exportProducts(ExportFormat.xlsx),
                        icon: const Icon(Icons.table_chart_outlined, size: 16),
                        label: const Text('Ekspor Excel (XLSX)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Ekspor Penjualan
                _buildExportCard(
                  context: context,
                  title: 'Riwayat & Rincian Penjualan',
                  subtitle: 'Data penjualan transaksi per rentang tanggal beserta detail produk terjual, kasir, metode pembayaran, dan laba kotor.',
                  icon: Icons.point_of_sale_outlined,
                  iconBgColor: Colors.green.shade100,
                  iconColor: Colors.green.shade800,
                  actions: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.showExportFilterDialog(ExportType.sales),
                        icon: const Icon(Icons.date_range_outlined, size: 16),
                        label: const Text('Pilih Rentang & Ekspor'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Ekspor Mutasi Stok (Kartu Stok)
                _buildExportCard(
                  context: context,
                  title: 'Mutasi Stok & Kartu Stok',
                  subtitle: 'Jejak mutasi stok per tanggal (penjualan, pembelian, opname, koreksi stok, void) dengan perhitungan sisa stok fisik.',
                  icon: Icons.history_outlined,
                  iconBgColor: Colors.amber.shade100,
                  iconColor: Colors.amber.shade900,
                  actions: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.showExportFilterDialog(ExportType.stockCard),
                        icon: const Icon(Icons.date_range_outlined, size: 16),
                        label: const Text('Pilih Rentang & Ekspor'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Ekspor Pembelian
                _buildExportCard(
                  context: context,
                  title: 'Data Pembelian & Kulakan',
                  subtitle: 'Riwayat penerimaan barang dari pemasok, nomor referensi, rincian barang masuk, harga modal beli, dan total faktur.',
                  icon: Icons.shopping_bag_outlined,
                  iconBgColor: Colors.teal.shade100,
                  iconColor: Colors.teal.shade800,
                  actions: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.showExportFilterDialog(ExportType.purchases),
                        icon: const Icon(Icons.date_range_outlined, size: 16),
                        label: const Text('Pilih Rentang & Ekspor'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Ekspor Hasil Stock Opname
                _buildExportCard(
                  context: context,
                  title: 'Hasil Stock Opname',
                  subtitle: 'Daftar sesi hitung fisik barang gudang, selisih stok sistem vs fisik, serta nilai deviasi modal barang.',
                  icon: Icons.checklist_rtl_outlined,
                  iconBgColor: Colors.purple.shade100,
                  iconColor: Colors.purple.shade800,
                  actions: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.showExportFilterDialog(ExportType.stockOpname),
                        icon: const Icon(Icons.date_range_outlined, size: 16),
                        label: const Text('Pilih Rentang & Ekspor'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Ekspor Log Jejak Aktivitas (Audit)
                Obx(() {
                  if (!controller.canViewAudit) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildExportCard(
                        context: context,
                        title: 'Log Jejak Aktivitas (Audit Trail)',
                        subtitle: 'Catatan jejak aktivitas sensitif pengguna dan sistem (perubahan harga, koreksi stok, void kasir, otentikasi).',
                        icon: Icons.security_outlined,
                        iconBgColor: Colors.orange.shade100,
                        iconColor: Colors.orange.shade900,
                        actions: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FilledButton.icon(
                              onPressed: () => controller.showExportFilterDialog(ExportType.auditLog),
                              icon: const Icon(Icons.date_range_outlined, size: 16),
                              label: const Text('Pilih Rentang & Ekspor'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImportCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required ImportTemplateType type,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: iconBgColor,
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unduh Template:',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => controller.downloadTemplate(type, isCsv: true),
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('CSV'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () => controller.downloadTemplate(type, isCsv: false),
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('Excel (XLSX)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () => controller.startImport(type),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text('Mulai Impor $title'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required Widget actions,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: iconBgColor,
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            actions,
          ],
        ),
      ),
    );
  }
}
