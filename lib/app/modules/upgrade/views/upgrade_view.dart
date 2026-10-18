import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/feature_gate.dart';
import '../controllers/upgrade_controller.dart';

class UpgradeView extends GetView<UpgradeController> {
  const UpgradeView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Feature? requestedFeature = Get.arguments is Map ? Get.arguments['feature'] as Feature? : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade Paket POS Me'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Buka Potensi Penuh Usaha Anda',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Obx(
                  () => Text(
                    'Paket Saat Ini: ${FeatureGate.to.tier.value.displayName.toUpperCase()}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),

                if (requestedFeature != null) ...[
                  Card(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: theme.colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Fitur "${requestedFeature.displayName}" membutuhkan paket lisensi yang lebih tinggi.',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Overview of tiers
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tingkatan Paket:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Divider(height: 24),
                        _buildTierRow(
                          context,
                          title: 'Gratis',
                          desc: 'Kasir, barcode scanner, nota, maks 10 produk aktif.',
                          isCurrent: FeatureGate.to.tier.value.name == 'free',
                        ),
                        const SizedBox(height: 16),
                        _buildTierRow(
                          context,
                          title: 'Semi Premium',
                          desc: 'Produk tanpa batas, stock opname, pembelian/suplier, import/export, laporan lengkap.',
                          isCurrent: FeatureGate.to.tier.value.name == 'semi',
                        ),
                        const SizedBox(height: 16),
                        _buildTierRow(
                          context,
                          title: 'Premium',
                          desc: 'Semua fitur Semi + Tim (multi-user), absensi staf, multi-device lokal.',
                          isCurrent: FeatureGate.to.tier.value.name == 'premium',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sistem pembayaran resmi akan hadir pada pembaruan mendatang. Hubungi admin atau simulasi lisensi melalui pengaturan.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Kembali ke Aplikasi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTierRow(BuildContext context, {required String title, required String desc, required bool isCurrent}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isCurrent ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outline,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Aktif', style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimaryContainer)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(desc, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
