import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

import '../../../core/services/pdf/label_pdf_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../controllers/product_labels_controller.dart';

class ProductLabelsView extends GetView<ProductLabelsController> {
  const ProductLabelsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!controller.canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cetak Label Produk')),
        body: const ErrorState(
          title: 'Akses Ditolak',
          message: 'Anda tidak memiliki izin untuk melihat produk.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isDesktop = screenWidth >= 960;
        final isTabletLandscape = screenWidth >= 720 && screenWidth < 960;
        final isSplitLayout = isDesktop || isTabletLandscape;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Cetak Label Barcode'),
            actions: [
              IconButton(
                tooltip: 'Simpan / Bagikan PDF',
                icon: const Icon(Icons.share_outlined),
                onPressed: controller.sharePdf,
              ),
              IconButton(
                tooltip: 'Cetak ke Printer',
                icon: const Icon(Icons.print),
                onPressed: controller.printPdf,
              ),
            ],
          ),
          body: isSplitLayout
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Panel Kiri: Pengaturan & Pemilihan Produk
                    SizedBox(
                      width: isDesktop
                          ? (screenWidth * 0.42).clamp(380.0, 500.0)
                          : screenWidth * 0.48,
                      child: _buildControlsAndList(context, theme),
                    ),
                    const VerticalDivider(width: 1),
                    // Panel Kanan: Pratinjau PDF
                    Expanded(
                      child: _buildPreviewPane(context, theme),
                    ),
                  ],
                )
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      Container(
                        color: theme.colorScheme.surface,
                        child: Obx(() {
                          final count = controller.selectedProductIds.length;
                          return TabBar(
                            tabs: [
                              Tab(
                                icon: const Icon(Icons.tune),
                                text: count > 0 ? 'Pilihan ($count)' : 'Pilihan Label',
                              ),
                              const Tab(
                                icon: Icon(Icons.visibility),
                                text: 'Pratinjau PDF',
                              ),
                            ],
                          );
                        }),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildControlsAndList(context, theme),
                            _buildPreviewPane(context, theme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          bottomNavigationBar: isSplitLayout
              ? null
              : SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Obx(() {
                      final hasSelection = controller.selectedProductIds.isNotEmpty;
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasSelection ? controller.sharePdf : null,
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text('Simpan PDF'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: hasSelection ? controller.printPdf : null,
                              icon: const Icon(Icons.print, size: 18),
                              label: Text('Cetak (${controller.totalLabelsCount})'),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildControlsAndList(BuildContext context, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Tip Scanner 1D / 2D
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tip: Scanner 1D tidak bisa membaca QR. Gunakan Code128, atau scanner 2D/kamera untuk QR.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Warning Banner jika barcode berisiko terlalu panjang
        Obx(() {
          final warnings = controller.currentWarnings;
          if (warnings.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Peringatan Kerapatan Barcode',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...warnings.map((w) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $w', style: const TextStyle(fontSize: 12)),
                    )),
              ],
            ),
          );
        }),

        // 3. Konfigurasi Label Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pengaturan Format & Template',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Format Barcode (Code128 / QR)
                const Text('Format Barcode:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Obx(() => SegmentedButton<LabelBarcodeFormat>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: LabelBarcodeFormat.code128,
                              label: Text('Code128 (1D)'),
                              icon: Icon(Icons.linear_scale, size: 18),
                            ),
                            ButtonSegment(
                              value: LabelBarcodeFormat.qr,
                              label: Text('QR Code (2D)'),
                              icon: Icon(Icons.qr_code, size: 18),
                            ),
                          ],
                          selected: {controller.selectedFormat.value},
                          onSelectionChanged: (set) {
                            controller.selectedFormat.value = set.first;
                          },
                        )),
                  ),
                ),
                const SizedBox(height: 12),

                // Template Ukuran
                const Text('Template Ukuran Label:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Obx(() => DropdownButtonFormField<LabelTemplateType>(
                      isExpanded: true,
                      initialValue: controller.selectedTemplate.value,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: LabelTemplateType.roll3Col40x20,
                          child: Text(
                            '3 Kolom (40 x 20 mm) - Roll Stiker',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        DropdownMenuItem(
                          value: LabelTemplateType.roll2Col50x30,
                          child: Text(
                            '2 Kolom (50 x 30 mm) - Roll Stiker',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        DropdownMenuItem(
                          value: LabelTemplateType.a4Grid,
                          child: Text(
                            'A4 Grid Bebas (24 label / lembar HVS)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) controller.selectedTemplate.value = val;
                      },
                    )),
                const SizedBox(height: 12),

                // Toggle Tampilkan Harga
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tampilkan Harga Jual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Mencetak nominal rupiah pada label'),
                      value: controller.showPrice.value,
                      onChanged: (val) => controller.showPrice.value = val,
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Bagian Pemilihan Produk Header
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'Daftar Produk',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Obx(() => Text(
                  '${controller.selectedProductIds.length} produk terpilih (${controller.totalLabelsCount} label)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )),
          ],
        ),
        const SizedBox(height: 8),

        // Filter Cepat & Aksi Massal
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Hanya Internal'),
              onPressed: controller.selectAllInternalProducts,
              visualDensity: VisualDensity.compact,
            ),
            ActionChip(
              avatar: const Icon(Icons.select_all, size: 16),
              label: const Text('Pilih Semua'),
              onPressed: controller.selectAllFiltered,
              visualDensity: VisualDensity.compact,
            ),
            ActionChip(
              avatar: const Icon(Icons.clear, size: 16),
              label: const Text('Batal Pilih'),
              onPressed: controller.deselectAll,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Kolom Pencarian
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama, SKU, atau kode barcode...',
            prefixIcon: Icon(Icons.search, size: 20),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (val) => controller.searchQuery.value = val,
        ),
        const SizedBox(height: 12),

        // List Produk
        Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: LoadingIndicator()));
          }

          final products = controller.filteredProducts;
          if (products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Tidak ada produk yang cocok.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final product = products[index];
              final isSelected = controller.selectedProductIds.contains(product.id);
              final copies = controller.productCopies[product.id] ?? 1;
              final isManufacturer = product.codeType == 'manufacturer';
              final code = product.barcode ?? product.internalCode ?? '-';

              return InkWell(
                onTap: () => controller.toggleProductSelection(product.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => controller.toggleProductSelection(product.id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isManufacturer ? Colors.grey.shade200 : theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isManufacturer ? 'Pabrik' : (product.codeType == 'internal_qr' ? 'QR' : 'Code128'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isManufacturer ? Colors.grey.shade700 : theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Kode: $code • ${formatRupiah(product.sellPrice)}',
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: const Icon(Icons.remove, size: 16),
                                tooltip: 'Kurang Salinan',
                                onPressed: copies > 1 ? () => controller.updateCopies(product.id, copies - 1) : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '$copies',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: const Icon(Icons.add, size: 16),
                                tooltip: 'Tambah Salinan',
                                onPressed: () => controller.updateCopies(product.id, copies + 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  Widget _buildPreviewPane(BuildContext context, ThemeData theme) {
    return Obx(() {
      final selectedCount = controller.selectedProductIds.length;
      if (selectedCount == 0) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.label_off_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Belum ada produk yang dipilih',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Pilih satu atau beberapa produk dari tab pilihan untuk melihat pratinjau label.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }

      // Re-trigger layout whenever template, format, showPrice, or copies change
      controller.selectedTemplate.value;
      controller.selectedFormat.value;
      controller.showPrice.value;
      controller.productCopies.length;

      return PdfPreview(
        build: (format) => controller.generatePdfBytes(),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: 'label_produk.pdf',
        loadingWidget: const Center(child: LoadingIndicator()),
      );
    });
  }
}
