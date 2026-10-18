import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/printing/receipt_mode.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../controllers/printer_settings_controller.dart';

class PrinterSettingsView extends GetView<PrinterSettingsController> {
  const PrinterSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!controller.canManageSettings) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan Printer')),
        body: const ErrorState(
          title: 'Akses Ditolak',
          message: 'Anda tidak memiliki hak akses mengelola pengaturan printer (settings.manage).',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Printer Thermal'),
        actions: [
          IconButton(
            tooltip: 'Segarkan Perangkat',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshDevices,
          ),
        ],
      ),
      body: Obx(() {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Jenis Koneksi Printer
                _buildSectionHeader(theme, '1. Jenis Koneksi Printer', Icons.print),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'bluetooth',
                              label: const Text('Bluetooth'),
                              icon: const Icon(Icons.bluetooth),
                              enabled: controller.isAndroid,
                            ),
                            ButtonSegment(
                              value: 'usb_windows',
                              label: const Text('USB Windows'),
                              icon: const Icon(Icons.usb),
                              enabled: controller.isWindows,
                            ),
                            const ButtonSegment(
                              value: 'lan',
                              label: Text('LAN (Wi-Fi)'),
                              icon: Icon(Icons.network_check),
                            ),
                            const ButtonSegment(
                              value: 'pdf_only',
                              label: Text('PDF Saja'),
                              icon: Icon(Icons.picture_as_pdf),
                            ),
                          ],
                          selected: {controller.selectedType.value},
                          onSelectionChanged: (set) => controller.setPrinterType(set.first),
                        ),
                        const SizedBox(height: 12),
                        _buildConnectionDetails(theme),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Format Kertas & Layout Struk
                _buildSectionHeader(theme, '2. Format Kertas & Karakter', Icons.receipt_long),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Lebar Kertas
                        Row(
                          children: [
                            const Expanded(
                              flex: 2,
                              child: Text('Lebar Kertas Roll:', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              flex: 3,
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: '58', label: Text('58 mm (Kasir Kecil)')),
                                  ButtonSegment(value: '80', label: Text('80 mm (Kasir Lebar)')),
                                ],
                                selected: {controller.paperWidth.value},
                                onSelectionChanged: (set) => controller.setPaperWidth(set.first),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Jumlah Karakter per Baris
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Karakter per Baris:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    'Default: 32 untuk 58 mm, 48 untuk 80 mm',
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.remove),
                                    onPressed: controller.charsPerLine.value > 24
                                        ? () => controller.charsPerLine.value--
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      '${controller.charsPerLine.value} kolom',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.add),
                                    onPressed: controller.charsPerLine.value < 64
                                        ? () => controller.charsPerLine.value++
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Opsi Potong Kertas
                        Row(
                          children: [
                            const Expanded(
                              flex: 2,
                              child: Text('Pemotong Kertas (Auto Cut):', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: controller.cutMode.value,
                                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                                items: const [
                                  DropdownMenuItem(value: 'partial', child: Text('Potong Sebagian (Partial)')),
                                  DropdownMenuItem(value: 'full', child: Text('Potong Penuh (Full)')),
                                  DropdownMenuItem(value: 'none', child: Text('Tidak Potong (Manual Sobek)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) controller.cutMode.value = val;
                                },
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Feed Lines
                        Row(
                          children: [
                            const Expanded(
                              flex: 2,
                              child: Text('Baris Kosong Akhir (Feed):', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.remove),
                                    onPressed: controller.feedLines.value > 1
                                        ? () => controller.feedLines.value--
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      '${controller.feedLines.value} baris',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.add),
                                    onPressed: controller.feedLines.value < 10
                                        ? () => controller.feedLines.value++
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Otomasi & Fitur Tambahan
                _buildSectionHeader(theme, '3. Otomasi & Laci Kasir (Cash Drawer)', Icons.tune),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Mode Struk
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mode Struk Pasca-Transaksi:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<ReceiptMode>(
                              initialValue: controller.receiptMode.value,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: ReceiptMode.ask,
                                  child: Text('Tanya / Dialog Sukses (Default)'),
                                ),
                                DropdownMenuItem(
                                  value: ReceiptMode.always,
                                  child: Text('Selalu Cetak Otomatis ke Printer'),
                                ),
                                DropdownMenuItem(
                                  value: ReceiptMode.never,
                                  child: Text('Tanpa Struk (Langsung Transaksi Baru)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) controller.receiptMode.value = val;
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              controller.receiptMode.value == ReceiptMode.ask
                                  ? 'Menampilkan layar sukses dengan pilihan Cetak Struk, Simpan PDF, atau Transaksi Baru.'
                                  : controller.receiptMode.value == ReceiptMode.always
                                      ? 'Mencetak otomatis ke printer thermal default lalu membuka layar sukses ringkas.'
                                      : 'Tidak mencetak struk dan langsung fokus kembali ke kasir untuk transaksi berikutnya.',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Laci Kasir (Cash Drawer)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Buka Laci Kasir (Cash Drawer)', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Mengirim sinyal pulse RJ11 ke laci kasir saat transaksi selesai'),
                          value: controller.cashDrawer.value,
                          onChanged: (val) => controller.cashDrawer.value = val,
                        ),

                        if (controller.cashDrawer.value) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(
                                flex: 2,
                                child: Text('Pin RJ11 Laci:', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<int>(
                                  initialValue: controller.drawerPin.value,
                                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                                  items: const [
                                    DropdownMenuItem(value: 0, child: Text('Pin 2 (Standar ESC/POS)')),
                                    DropdownMenuItem(value: 1, child: Text('Pin 5 (Alternatif)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) controller.drawerPin.value = val;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: controller.testCashDrawer,
                                child: const Text('Uji Laci'),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 24),

                        // Salinan Struk
                        Row(
                          children: [
                            const Expanded(
                              flex: 2,
                              child: Text('Jumlah Salinan Struk:', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.remove),
                                    onPressed: controller.copies.value > 1
                                        ? () => controller.copies.value--
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      '${controller.copies.value} salinan',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.add),
                                    onPressed: controller.copies.value < 5
                                        ? () => controller.copies.value++
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Tombol Aksi (Tes Cetak & Simpan)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: controller.isTestingPrint.value ? null : controller.runTestPrint,
                        icon: controller.isTestingPrint.value
                            ? const SizedBox(width: 18, height: 18, child: LoadingIndicator())
                            : const Icon(Icons.print_outlined),
                        label: const Text('TES CETAK STRUK', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: controller.saveSettings,
                        icon: const Icon(Icons.save),
                        label: const Text('SIMPAN PENGATURAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildConnectionDetails(ThemeData theme) {
    final type = controller.selectedType.value;

    if (type == 'bluetooth') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Petunjuk: Pasangkan (Pair) printer di pengaturan Bluetooth perangkat HP terlebih dahulu sebelum memilih di daftar ini.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (controller.isLoadingDevices.value)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: LoadingIndicator()))
          else if (controller.bluetoothDevices.isEmpty)
            Column(
              children: [
                const Text('Tidak ada perangkat Bluetooth yang terpasang.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: controller.refreshDevices,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Pindai Ulang Bluetooth'),
                ),
              ],
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: controller.selectedTarget.value.isNotEmpty &&
                      controller.bluetoothDevices.any((d) => d.macAdress == controller.selectedTarget.value)
                  ? controller.selectedTarget.value
                  : null,
              decoration: const InputDecoration(
                labelText: 'Pilih Printer Bluetooth',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
              items: controller.bluetoothDevices.map((d) {
                return DropdownMenuItem<String>(
                  value: d.macAdress,
                  child: Text('${d.name} (${d.macAdress})'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) controller.selectedTarget.value = val;
              },
            ),
        ],
      );
    }

    if (type == 'usb_windows') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Data cetak dikirim via Windows Print Spooler (RAW ESC/POS). Pastikan driver printer USB thermal terpasang di Windows.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (controller.isLoadingDevices.value)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: LoadingIndicator()))
          else if (controller.windowsPrinters.isEmpty)
            Column(
              children: [
                const Text('Tidak ada printer terpasang di sistem Windows.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: controller.refreshDevices,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Pindai Ulang Printer Windows'),
                ),
              ],
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: controller.selectedTarget.value.isNotEmpty &&
                      controller.windowsPrinters.any((p) => p.name == controller.selectedTarget.value)
                  ? controller.selectedTarget.value
                  : null,
              decoration: const InputDecoration(
                labelText: 'Pilih Printer Windows (Spooler)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
              items: controller.windowsPrinters.map((p) {
                return DropdownMenuItem<String>(
                  value: p.name,
                  child: Text('${p.name}${p.isDefault ? " (Default)" : ""}'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) controller.selectedTarget.value = val;
              },
            ),
        ],
      );
    }

    if (type == 'lan') {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller.lanIpController,
                  decoration: const InputDecoration(
                    labelText: 'Alamat IP Printer LAN',
                    hintText: 'Contoh: 192.168.1.100',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.router),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: controller.lanPortController,
                  decoration: const InputDecoration(
                    labelText: 'Port (Default 9100)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: controller.isTestingConnection.value ? null : controller.testLanConnection,
                icon: controller.isTestingConnection.value
                    ? const SizedBox(width: 16, height: 16, child: LoadingIndicator())
                    : const Icon(Icons.cable),
                label: const Text('Uji IP'),
              ),
            ],
          ),
        ],
      );
    }

    // Default: 'pdf_only'
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.picture_as_pdf, color: Colors.blue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Mode virtual PDF aktif. Struk kasir akan selalu ditampilkan melalui dialog pratinjau PDF dan dapat dicetak atau dibagikan sebagai dokumen.',
            ),
          ),
        ],
      ),
    );
  }
}
