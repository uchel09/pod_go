import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/tier_enum.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../controllers/developer_panel_controller.dart';

class DeveloperPanelView extends GetView<DeveloperPanelController> {
  const DeveloperPanelView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Developer (Simulasi)'),
        actions: [
          IconButton(
            tooltip: 'Segarkan Data',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.refreshData(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.errorMessage.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_person_outlined,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Akses Dibatasi',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          controller.errorMessage.value,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.tonal(
                          onPressed: () => Get.back(),
                          child: const Text('Kembali'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Banner Simulasi
                      _buildSimulationHeader(context),
                      const SizedBox(height: 20),

                      // Status Toko & Tier Aktif
                      _buildStatusCard(context),
                      const SizedBox(height: 20),

                      // Kontrol Tier Instan
                      _buildSectionTitle(context, '1. PENGATURAN TIER INSTAN'),
                      const SizedBox(height: 10),
                      _buildTierControls(context),
                      const SizedBox(height: 24),

                      // Simulasi Skenario Pembayaran & Kedaluwarsa
                      _buildSectionTitle(
                          context, '2. SIMULASI SKENARIO LISENSI & PEMBAYARAN'),
                      const SizedBox(height: 10),
                      _buildScenarioControls(context),
                      const SizedBox(height: 24),

                      // Generator Data Dummy
                      _buildSectionTitle(context, '3. GENERATOR DATA SAMPEL (DUMMY)'),
                      const SizedBox(height: 10),
                      _buildSampleDataControls(context),
                      const SizedBox(height: 28),

                      // Jejak Audit Terakhir
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionTitle(
                              context, '4. 50 AUDIT LOG TERAKHIR'),
                          Text(
                            '${controller.auditLogs.length} entri',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildAuditLogsSection(context),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            if (controller.isLoading.value)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSimulationHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.build_circle_outlined, color: Colors.amber.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode Pengujian & Developer POS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Panel ini hanya aktif saat kSimulationMode = true. Semua manipulasi lisensi bersifat lokal.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final tier = controller.currentTier.value;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: tier == Tier.premium
                  ? Colors.purple.shade100
                  : (tier == Tier.semi
                      ? Colors.blue.shade100
                      : Colors.grey.shade200),
              child: Icon(
                tier == Tier.premium
                    ? Icons.workspace_premium
                    : (tier == Tier.semi
                        ? Icons.verified
                        : Icons.storefront),
                color: tier == Tier.premium
                    ? Colors.purple.shade800
                    : (tier == Tier.semi
                        ? Colors.blue.shade800
                        : Colors.grey.shade800),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tier Aktif: ${tier.displayName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Data Sampel di Database: ${controller.sampleProductCount.value} produk, ${controller.sampleSaleCount.value} transaksi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  Widget _buildTierControls(BuildContext context) {
    final currentTier = controller.currentTier.value;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonalIcon(
          onPressed: currentTier == Tier.free
              ? null
              : () => controller.setInstantTier(Tier.free),
          icon: const Icon(Icons.money_off),
          label: const Text('Set Gratis'),
        ),
        FilledButton.tonalIcon(
          onPressed: currentTier == Tier.semi
              ? null
              : () => controller.setInstantTier(Tier.semi),
          icon: const Icon(Icons.star_half),
          label: const Text('Set Semi Premium (30 Hari)'),
        ),
        FilledButton.tonalIcon(
          onPressed: currentTier == Tier.premium
              ? null
              : () => controller.setInstantTier(Tier.premium),
          icon: const Icon(Icons.stars),
          label: const Text('Set Premium (30 Hari)'),
        ),
      ],
    );
  }

  Widget _buildScenarioControls(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: () => controller.simulatePaymentFailure(),
          icon: const Icon(Icons.credit_card_off_outlined, color: Colors.orange),
          label: const Text('Simulasi Gagal Bayar'),
        ),
        OutlinedButton.icon(
          onPressed: () => controller.simulateExpiredLicense(),
          icon: const Icon(Icons.timer_off_outlined, color: Colors.deepOrange),
          label: const Text('Simulasi Lisensi Expired'),
        ),
        OutlinedButton.icon(
          onPressed: () => controller.resetToFree(),
          icon: const Icon(Icons.restart_alt, color: Colors.red),
          label: const Text('Reset ke Kondisi Awal (Gratis)'),
        ),
      ],
    );
  }

  Widget _buildSampleDataControls(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: () => controller.generateSampleData(),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Generate 50 Produk & Transaksi Sampel'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade300),
          ),
          onPressed: controller.sampleProductCount.value == 0 &&
                  controller.sampleSaleCount.value == 0
              ? null
              : () async {
                  final confirmed = await ConfirmDialog.show(
                    context: context,
                    title: 'Hapus Data Sampel?',
                    message:
                        'Aksi ini HANYA akan menghapus data dengan label [SAMPLE] / INV-SMPL-.\n'
                        'Data riil toko dan inventori pengguna tidak akan disentuh.',
                    confirmText: 'Ya, Hapus Sampel',
                    isDestructive: true,
                  );
                  if (confirmed == true) {
                    controller.deleteSampleData();
                  }
                },
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(
            'Hapus Semua Data Sampel (${controller.sampleProductCount.value + controller.sampleSaleCount.value})',
          ),
        ),
      ],
    );
  }

  Widget _buildAuditLogsSection(BuildContext context) {
    final theme = Theme.of(context);
    final logs = controller.auditLogs;

    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: const Center(
          child: Text('Belum ada jejak audit yang tercatat.'),
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final log = logs[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.history,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              log.action,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              'Entitas: ${log.entity} (ID: ${log.entityId ?? '-'}) • ${log.detail ?? '-'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              dateFormat.format(log.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          );
        },
      ),
    );
  }
}
