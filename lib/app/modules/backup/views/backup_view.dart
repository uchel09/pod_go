import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/models/backup_models.dart';
import '../controllers/backup_controller.dart';

class BackupView extends GetView<BackupController> {
  const BackupView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pusat Cadangan & Pemulihan Data'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.backup_outlined), text: 'Backup Manual'),
              Tab(icon: Icon(Icons.restore_outlined), text: 'Pemulihan (Restore)'),
              Tab(icon: Icon(Icons.auto_mode_outlined), text: 'Auto-Backup (Cloud)'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Segarkan Info',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                controller.loadLastBackupInfo();
                controller.loadAutoBackupConfig();
              },
            ),
          ],
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          return TabBarView(
            children: [
              _buildManualBackupTab(context),
              _buildRestoreTab(context),
              _buildAutoBackupTab(context),
            ],
          );
        }),
      ),
    );
  }

  // =========================================================================
  // TAB 1: BACKUP MANUAL (SEMUA TIER)
  // =========================================================================

  Widget _buildManualBackupTab(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24.0 : 16.0,
            vertical: 20.0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLastBackupStatusCard(context),
                  const SizedBox(height: 16),
                  _buildSecurityNoticeCard(context),
                  const SizedBox(height: 24),
                  _buildBackupActionButton(context),
                  if (controller.latestBackupResult.value != null) ...[
                    const SizedBox(height: 24),
                    _buildBackupResultCard(context),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLastBackupStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final info = controller.lastBackupInfo.value;

    if (info == null) {
      return Card(
        elevation: 0,
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 40, color: Colors.amber.shade900),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Belum Pernah Backup',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Aplikasi ini beroperasi offline dan tidak menyimpan data di cloud server. Sangat disarankan untuk segera mencadangkan data usaha Anda sekarang.',
                      style: TextStyle(color: Colors.amber.shade900, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isOutdated = info.daysAgo >= 7;
    final dateFormatted = DateFormat('EEEE, dd MMMM yyyy HH:mm').format(info.backedUpAt);

    return Card(
      elevation: 0,
      color: isOutdated
          ? Colors.orange.shade50
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOutdated ? Colors.orange.shade300 : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOutdated ? Icons.history_toggle_off : Icons.check_circle_outline,
                  color: isOutdated ? Colors.orange.shade800 : theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Status Cadangan Terakhir',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOutdated ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOutdated ? Colors.orange.shade300 : Colors.green.shade300,
                    ),
                  ),
                  child: Text(
                    isOutdated
                        ? 'Perlu Backup (${info.daysAgo} hari lalu)'
                        : (info.daysAgo == 0 ? 'Aman (Hari ini)' : 'Aman (${info.daysAgo} hari lalu)'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isOutdated ? Colors.orange.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WAKTU BACKUP', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(dateFormatted, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('UKURAN ARSIP', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(info.formattedSize, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            if (info.fileName != null) ...[
              const SizedBox(height: 12),
              Text(
                'Nama Berkas: ${info.fileName}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityNoticeCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Peringatan Keamanan & Penyimpanan',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Berkas backup (.zip) berisi seluruh database usaha termasuk riwayat transaksi dan log audit. Simpan berkas ini di tempat yang aman (flashdisk USB, Google Drive pribadi, atau kirim ke WhatsApp sendiri).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupActionButton(BuildContext context) {
    return Obx(() {
      final isBackingUp = controller.isBackingUp.value;

      return SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: isBackingUp ? null : () => controller.createBackup(),
          icon: isBackingUp
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(
            isBackingUp ? 'Sedang Membuat Backup Data...' : 'Backup Sekarang',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    });
  }

  Widget _buildBackupResultCard(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.latestBackupResult.value;
    if (result == null) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade800, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Backup Selesai Dibuat!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
                Text(
                  result.formattedSize,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nama Berkas: ${result.fileName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jumlah Produk: ${result.metadata.productCount} | Total Transaksi: ${result.metadata.transactionCount}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  Text(
                    'Format: SQLite Database Snapshot + Metadata JSON (ZIP)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => controller.saveToFolder(),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Simpan ke Folder'),
                ),
                OutlinedButton.icon(
                  onPressed: () => controller.shareBackup(),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Kirim / Bagikan (Share)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 2: PEMULIHAN (RESTORE)
  // =========================================================================

  Widget _buildRestoreTab(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24.0 : 16.0,
            vertical: 20.0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 36, color: Colors.red.shade800),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Perhatian Sebelum Melakukan Restore',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Pemulihan akan menimpa seluruh database aktif dengan isi berkas backup. '
                                  'Sebelum penimpaan dilakukan, sistem WAJIB membuat backup otomatis '
                                  'kondisi saat ini (pre_restore) sebagai jaminan keselamatan data Anda.',
                                  style: TextStyle(color: Colors.red.shade900, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pilih Berkas Backup (.zip)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sistem akan memvalidasi struktur zip, versi skema, dan integritas SQLite sebelum meminta konfirmasi Anda.',
                            style: TextStyle(color: Colors.grey, height: 1.3),
                          ),
                          const SizedBox(height: 20),
                          Obx(() {
                            final isValidating = controller.isValidatingRestore.value;
                            final isRestoring = controller.isRestoring.value;

                            return SizedBox(
                              height: 50,
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: (isValidating || isRestoring)
                                    ? null
                                    : () => _handlePickAndRestore(context),
                                icon: (isValidating || isRestoring)
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.file_open_outlined),
                                label: Text(
                                  isValidating
                                      ? 'Memeriksa Integritas Backup...'
                                      : (isRestoring ? 'Memulihkan Data...' : 'Pilih Berkas & Periksa Data'),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePickAndRestore(BuildContext context) async {
    final preview = await controller.pickAndValidateRestoreFile();
    if (preview != null && context.mounted) {
      _showHardConfirmationDialog(context, preview);
    }
  }

  /// Dialog Konfirmasi Keras dengan perbandingan data saat ini vs data backup
  void _showHardConfirmationDialog(BuildContext context, RestorePreview preview) {
    final theme = Theme.of(context);
    final backupDateStr = DateFormat('dd MMM yyyy HH:mm').format(DateTime.tryParse(preview.backupMetadata.timestamp) ?? preview.currentDate);
    final currentDateStr = DateFormat('dd MMM yyyy HH:mm').format(preview.currentDate);

    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            Icon(Icons.report_problem, color: Colors.red.shade800),
            const SizedBox(width: 10),
            const Expanded(child: Text('Konfirmasi Pemulihan Data')),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Periksa perbandingan antara kondisi data saat ini dengan data dalam file backup yang akan dipulihkan:',
                  style: TextStyle(fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.4),
                      2: FlexColumnWidth(1.4),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
                        children: const [
                          Padding(padding: EdgeInsets.all(8), child: Text('Parameter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Kondisi Sekarang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Isi File Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(8), child: Text('Nama Toko', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(preview.currentStoreName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(preview.backupMetadata.storeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.blue))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(8), child: Text('Waktu Data', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(currentDateStr, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(backupDateStr, style: const TextStyle(fontSize: 12, color: Colors.blue))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(8), child: Text('Total Transaksi', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${preview.currentTransactionCount}', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${preview.backupMetadata.transactionCount}', style: const TextStyle(fontSize: 12, color: Colors.blue))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(8), child: Text('Total Produk', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${preview.currentProductCount}', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${preview.backupMetadata.productCount}', style: const TextStyle(fontSize: 12, color: Colors.blue))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield, color: Colors.green.shade800, size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Sistem otomatis membuat backup pre_restore sebelum menimpa data. Jika restore gagal, data lama akan dikembalikan otomatis.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () async {
              Get.back(); // Tutup modal konfirmasi
              final success = await controller.executeRestore();
              if (success && context.mounted) {
                _showRestoreSuccessDialog(context);
              }
            },
            child: const Text('Lanjutkan & Pulihkan Data', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showRestoreSuccessDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text('Pemulihan Selesai!'),
          ],
        ),
        content: const Text(
          'Seluruh data berhasil dipulihkan dari berkas backup. '
          'Untuk menerapkan perubahan dan memperbarui seluruh antarmuka, '
          'aplikasi akan dimuat ulang ke layar awal.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => controller.reinitApp(),
            child: const Text('Muat Ulang Aplikasi Sekarang'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  // =========================================================================
  // TAB 3: AUTO-BACKUP (SEMI-PREMIUM KE ATAS)
  // =========================================================================

  Widget _buildAutoBackupTab(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlocked = controller.isAutoBackupUnlocked;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24.0 : 16.0,
            vertical: 20.0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isUnlocked) ...[
                    Card(
                      elevation: 0,
                      color: Colors.amber.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.amber.shade300),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => FeatureGate.to.requireFeature(Feature.autoBackup),
                        child: Padding(
                          padding: const EdgeInsets.all(18.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade200,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock, color: Colors.black87),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fitur Auto-Backup Terkunci (Semi-Premium)',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.brown.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Upgrade ke lisensi Semi-Premium untuk mengaktifkan pencadangan otomatis berkala ke folder cloud drive.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_sync_outlined, color: theme.colorScheme.primary, size: 28),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pencadangan Otomatis Terjadwal',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Simpan backup otomatis ke folder lokal / sinkronisasi cloud drive',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Obx(() => Switch(
                                    value: controller.autoBackupConfig.value.enabled,
                                    onChanged: (val) => controller.toggleAutoBackup(val),
                                  )),
                            ],
                          ),
                          const Divider(height: 28),

                          // Folder pilihan
                          const Text('Folder Tujuan Penyimpanan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Obx(() {
                            final folder = controller.autoBackupConfig.value.folderPath;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined, size: 22, color: Colors.grey),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      folder ?? 'Belum ada folder dipilih (Arahkan ke Google Drive / OneDrive)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: folder == null ? Colors.grey : theme.textTheme.bodyMedium?.color,
                                        fontWeight: folder == null ? FontWeight.normal : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => controller.pickAutoBackupFolder(),
                                    child: const Text('Pilih Folder'),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 18),

                          // Jadwal
                          const Text('Jadwal Eksekusi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Obx(() {
                            final schedule = controller.autoBackupConfig.value.schedule;
                            return SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'daily', label: Text('Harian (Setiap Hari)')),
                                ButtonSegment(value: 'weekly', label: Text('Mingguan (Setiap 7 Hari)')),
                              ],
                              selected: {schedule},
                              onSelectionChanged: (set) {
                                if (set.isNotEmpty) controller.updateSchedule(set.first);
                              },
                            );
                          }),
                          const SizedBox(height: 18),

                          // Batas rotasi
                          const Text('Rotasi Berkas (Jumlah Maksimal Disimpan):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Obx(() {
                            final maxFiles = controller.autoBackupConfig.value.maxFiles;
                            return Wrap(
                              spacing: 8,
                              children: [3, 5, 10, 15].map((count) {
                                final isSelected = maxFiles == count;
                                return ChoiceChip(
                                  label: Text('$count Berkas Terakhir'),
                                  selected: isSelected,
                                  onSelected: (_) => controller.updateMaxFiles(count),
                                );
                              }).toList(),
                            );
                          }),
                          const SizedBox(height: 20),

                          // Keterangan batasan tanpa background service
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade800, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pemberitahuan: Auto-backup berjalan saat aplikasi dibuka atau ditutup (tanpa background service). '
                                    'Arahkan folder ke Google Drive / OneDrive / Dropbox desktop agar otomatis terunggah ke cloud.',
                                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Tombol tes backup
                          Obx(() {
                            final isTesting = controller.isTestingAutoBackup.value;
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: isTesting ? null : () => controller.testAutoBackupNow(),
                                icon: isTesting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.play_circle_outline),
                                label: Text(
                                  isTesting ? 'Sedang Menjalankan Tes Backup...' : 'Tes Backup ke Folder Ini Sekarang',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
