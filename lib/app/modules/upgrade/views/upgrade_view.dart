import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/features/tier_enum.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/services/payment_gateway.dart';
import '../controllers/upgrade_controller.dart';

class UpgradeView extends GetView<UpgradeController> {
  const UpgradeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paket & Lisensi Aplikasi'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.isSimulationMode) ...[
                  _buildSimulationBanner(context),
                  const SizedBox(height: 20),
                ],

                if (controller.requestedFeature != null) ...[
                  _buildFeatureLockedAlert(context),
                  const SizedBox(height: 20),
                ],

                _buildHeaderSection(context),
                const SizedBox(height: 20),

                _buildDurationSelector(context),
                const SizedBox(height: 24),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 850;
                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildFreeCard(context)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSemiPremiumCard(context)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildPremiumCard(context)),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildFreeCard(context),
                          const SizedBox(height: 16),
                          _buildSemiPremiumCard(context),
                          const SizedBox(height: 16),
                          _buildPremiumCard(context),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimulationBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, color: Colors.amber.shade900, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'MODE SIMULASI AKTIF: Seluruh alur upgrade dan pembayaran di aplikasi ini adalah simulasi internal tanpa tagihan atau pembayaran riil.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureLockedAlert(BuildContext context) {
    final feat = controller.requestedFeature!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, color: Colors.red.shade800, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Fitur "${feat.displayName}" memerlukan lisensi Semi-Premium ke atas. Tingkatkan paket toko Anda untuk membuka fitur ini.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Pilih Paket Terbaik untuk Usaha Anda',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Obx(
          () => Text(
            'Paket Anda Saat Ini: ${controller.currentTier.value.displayName.toUpperCase()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationSelector(BuildContext context) {
    return Center(
      child: Obx(() {
        final current = controller.selectedDuration.value;
        return SegmentedButton<PlanDuration>(
          segments: const [
            ButtonSegment(
              value: PlanDuration.monthly,
              label: Text('Tagihan Bulanan'),
            ),
            ButtonSegment(
              value: PlanDuration.yearly,
              label: Text('Tagihan Tahunan (Hemat ~2 Bulan)'),
            ),
          ],
          selected: {current},
          onSelectionChanged: (set) {
            if (set.isNotEmpty) controller.setDuration(set.first);
          },
        );
      }),
    );
  }

  // --- KARTU 1: GRATIS ---
  Widget _buildFreeCard(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final isCurrent = controller.currentTier.value == Tier.free;

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCurrent) _buildCurrentBadge(),
              Text('Gratis', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Cocok untuk usaha rintisan mikro baru mulai.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('Rp 0', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const Text('Selamanya', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(height: 28),
              _buildFeatureItem('Kasir & cetak struk nota'),
              _buildFeatureItem('Scanner barcode HID & kamera'),
              _buildFeatureItem('Riwayat penjualan & void kasir'),
              _buildFeatureItem('Backup data manual (arsip ZIP)'),
              _buildFeatureItem('Maksimal 10 produk aktif', isHighlight: true),
              const SizedBox(height: 24),
              SizedBox(
                height: 44,
                child: isCurrent
                    ? OutlinedButton(
                        onPressed: null,
                        child: const Text('Paket Saat Ini'),
                      )
                    : OutlinedButton(
                        onPressed: () => controller.handleSelectTier(Tier.free),
                        child: const Text('Turunkan ke Gratis'),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // --- KARTU 2: SEMI PREMIUM ---
  Widget _buildSemiPremiumCard(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final isCurrent = controller.currentTier.value == Tier.semi;
      final price = controller.getSemiPrice();
      final isYearly = controller.selectedDuration.value == PlanDuration.yearly;

      return Card(
        elevation: 2,
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isCurrent ? Colors.green.shade700 : theme.colorScheme.primary,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCurrent)
                _buildCurrentBadge()
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'PALING POPULER',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              Text('Semi Premium', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              const SizedBox(height: 4),
              const Text('Solusi lengkap UMKM mandiri tanpa batas produk.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Text(formatRupiah(price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              Text(isYearly ? 'per tahun (~Rp 40.800/bln)' : 'per bulan', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(height: 28),
              _buildFeatureItem('Semua fitur paket Gratis'),
              _buildFeatureItem('Produk & kategori tanpa batas', isHighlight: true),
              _buildFeatureItem('Stock opname & koreksi stok', isHighlight: true),
              _buildFeatureItem('Pembelian & data suplier', isHighlight: true),
              _buildFeatureItem('Import & Export data CSV/Excel', isHighlight: true),
              _buildFeatureItem('Laporan laba kotor & HPP lengkap', isHighlight: true),
              _buildFeatureItem('Pencadangan otomatis (Auto-backup)', isHighlight: true),
              const SizedBox(height: 24),
              SizedBox(
                height: 44,
                child: isCurrent
                    ? OutlinedButton(
                        onPressed: null,
                        child: const Text('Paket Saat Ini'),
                      )
                    : FilledButton(
                        onPressed: () => controller.handleSelectTier(Tier.semi),
                        child: const Text('Pilih Semi Premium', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // --- KARTU 3: PREMIUM ---
  Widget _buildPremiumCard(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final isCurrent = controller.currentTier.value == Tier.premium;
      final price = controller.getPremiumPrice();
      final isYearly = controller.selectedDuration.value == PlanDuration.yearly;

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCurrent) _buildCurrentBadge(),
              Text('Premium', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Fitur kolaborasi tim & multi kasir.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Text(formatRupiah(price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              Text(isYearly ? 'per tahun (~Rp 82.500/bln)' : 'per bulan', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(height: 28),
              _buildFeatureItem('Semua fitur paket Semi-Premium'),
              _buildFeatureItem('Multi-user & manajemen karyawan*'),
              _buildFeatureItem('Absensi mandiri staf toko*'),
              _buildFeatureItem('Kustomisasi role & hak akses*'),
              _buildFeatureItem('Multi-device Host/Client LAN*'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '*Fitur Tim dalam tahap pengembangan (Fase 2). Tier tetap dapat dipilih untuk menguji gating sistem.',
                  style: TextStyle(fontSize: 11, color: Colors.black87, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: isCurrent
                    ? OutlinedButton(
                        onPressed: null,
                        child: const Text('Paket Saat Ini'),
                      )
                    : FilledButton.tonal(
                        onPressed: () => controller.handleSelectTier(Tier.premium),
                        child: const Text('Pilih Premium', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCurrentBadge() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Text(
          'PAKET AKTIF SAAT INI',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: isHighlight ? Colors.green.shade700 : Colors.blueGrey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
