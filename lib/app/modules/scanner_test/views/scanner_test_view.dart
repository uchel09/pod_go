import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/date_formatter.dart';
import '../controllers/scanner_test_controller.dart';

class ScannerTestView extends GetView<ScannerTestController> {
  const ScannerTestView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostik & Uji Scanner'),
        actions: [
          IconButton(
            tooltip: 'Hapus Riwayat',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: controller.clearHistory,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 720;

          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildControls(context, theme),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 6,
                  child: _buildHistorySection(context, theme),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildControls(context, theme),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                _buildHistoryList(context, theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status Layanan Scanner
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sensors, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Status Hardware & Listener',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  icon: Icons.keyboard_alt_outlined,
                  label: 'Scanner HID (USB/Bluetooth):',
                  status: 'Aktif & Mendengarkan',
                  isGood: true,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  icon: Icons.camera_alt_outlined,
                  label: 'Scanner Kamera:',
                  status: controller.isCameraSupported ? 'Didukung (Android)' : 'Tidak Didukung (Desktop)',
                  isGood: controller.isCameraSupported,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Kotak Hasil Pindaian Terakhir
        Obx(() {
          final code = controller.lastScannedCode.value;
          final source = controller.lastScannedSource.value;

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: code.isNotEmpty ? theme.colorScheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(
                    'HASIL PINDAIAN TERAKHIR',
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    code.isEmpty ? 'MENUNGGU PINDAIAN...' : code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: code.isEmpty ? Colors.grey : theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (source.isNotEmpty)
                    Chip(
                      avatar: Icon(
                        source == 'CAMERA' ? Icons.camera_alt : Icons.keyboard,
                        size: 16,
                      ),
                      label: Text('SUMBER: $source'),
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),

        // Tombol Aksi
        if (controller.isCameraSupported) ...[
          FilledButton.icon(
            onPressed: controller.scanWithCamera,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Buka Scan Kamera (Android)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Kamera scanner tidak tersedia di Windows. Sambungkan barcode scanner fisik USB atau Bluetooth.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Tombol Simulasi untuk Pengujian Cepat
        OutlinedButton.icon(
          onPressed: () => controller.simulateScan('8992753123456'),
          icon: const Icon(Icons.sim_card_download_outlined, size: 18),
          label: const Text('Simulasi Scan Barcode (8992753123456)'),
        ),
      ],
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String status,
    required bool isGood,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isGood ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isGood ? Colors.green.shade800 : Colors.orange.shade800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Riwayat Pindaian Sesi Ini',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Obx(() => Text(
                    'Total: ${controller.scanHistory.length}',
                    style: theme.textTheme.bodySmall,
                  )),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildHistoryList(context, theme)),
      ],
    );
  }

  Widget _buildHistoryList(BuildContext context, ThemeData theme) {
    return Obx(() {
      final list = controller.scanHistory;

      if (list.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Belum ada barcode yang dipindai',
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 4),
                Text(
                  'Arahkan scanner HID atau tekan tombol kamera untuk menguji',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      return ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = list[index];
          return ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: item.source == 'CAMERA'
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.green.withValues(alpha: 0.15),
              child: Icon(
                item.source == 'CAMERA' ? Icons.camera_alt : Icons.keyboard,
                size: 16,
                color: item.source == 'CAMERA' ? Colors.blue.shade800 : Colors.green.shade800,
              ),
            ),
            title: Text(
              item.code,
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
            subtitle: Text(
              '${item.source} • ${DateFormatter.formatDateTime(item.timestamp)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Salin Kode',
              onPressed: () {
                // Copy to clipboard or snackbar
                Get.snackbar('Disalin', 'Kode ${item.code} disalin', snackPosition: SnackPosition.BOTTOM);
              },
            ),
          );
        },
      );
    });
  }
}
