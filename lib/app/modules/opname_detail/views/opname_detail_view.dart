import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/opname_dao.dart';
import '../controllers/opname_detail_controller.dart';

class OpnameDetailView extends GetView<OpnameDetailController> {
  const OpnameDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Obx(() {
      if (controller.isLoading.value && controller.detail.value == null) {
        return const Scaffold(
          body: LoadingIndicator(message: 'Memuat sesi stock opname...'),
        );
      }

      final entry = controller.detail.value;
      if (entry == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Detail Opname')),
          body: const Center(child: Text('Data tidak ditemukan')),
        );
      }

      final isDraft = entry.isDraft;

      return Scaffold(
        appBar: AppBar(
          title: Text(entry.code),
          actions: [
            if (isDraft) ...[
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan Barcode Kamera',
                onPressed: controller.scanWithCamera,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Cari Produk',
                onPressed: () => _showProductSearchDialog(context),
              ),
              PopupMenuButton<String>(
                tooltip: 'Aksi Opname',
                onSelected: (val) {
                  if (val == 'load_all') {
                    controller.loadAllActiveProducts();
                  } else if (val == 'load_category') {
                    _showCategoryPickerDialog(context);
                  } else if (val == 'delete_draft') {
                    controller.deleteDraft();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'load_all',
                    child: Row(
                      children: [
                        Icon(Icons.select_all, size: 18),
                        SizedBox(width: 8),
                        Text('Muat Semua Produk Aktif'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'load_category',
                    child: Row(
                      children: [
                        Icon(Icons.category_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Muat Per Kategori'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete_draft',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Hapus Draft Opname', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: 'Cetak Dokumen Berita Acara',
                onPressed: controller.printReport,
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Simpan / Bagikan PDF',
                onPressed: controller.shareReportPdf,
              ),
            ],
          ],
        ),
        bottomNavigationBar: isDraft ? _buildBottomFinalizeBar(context, theme, entry) : null,
        body: SafeArea(
          child: Column(
            children: [
              // Summary Banner
              _buildSummaryHeader(theme, entry, isMobile),

              // Filter & Search Bar
              _buildSearchBar(theme, isMobile),

              // Items List
              Expanded(
                child: _buildItemsList(context, theme, entry, isMobile),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildSummaryHeader(ThemeData theme, OpnameDetailEntry entry, bool isMobile) {
    final dateStr = DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(entry.date);
    final isDraft = entry.isDraft;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isDraft ? Colors.amber.shade50.withValues(alpha: 0.5) : Colors.teal.shade50.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDraft ? Colors.orange.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDraft ? Colors.orange.shade400 : Colors.green.shade400,
                  ),
                ),
                child: Text(
                  isDraft ? 'STATUS: DRAFT HITUNG' : 'STATUS: FINAL (SELESAI)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDraft ? Colors.orange.shade900 : Colors.green.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(dateStr, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
              const Spacer(),
              if (entry.creatorName != null)
                Text('Petugas: ${entry.creatorName}', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
            ],
          ),
          const SizedBox(height: 10),

          // Mini statistics badges
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildStatBadge(theme, 'Total Item', '${entry.totalItems}', Colors.blue.shade800),
              _buildStatBadge(theme, 'Dihitung', '${entry.countedCount}', Colors.teal.shade800),
              if (isDraft && entry.uncountedCount > 0)
                _buildStatBadge(theme, 'Belum Dihitung', '${entry.uncountedCount}', Colors.grey.shade700),
              _buildStatBadge(
                theme,
                'Selisih',
                '${entry.diffCount} item',
                entry.diffCount > 0 ? Colors.red.shade800 : Colors.teal.shade800,
              ),
              if (controller.canViewCost)
                _buildStatBadge(
                  theme,
                  'Nilai Selisih',
                  formatRupiah(entry.totalDiffValue),
                  entry.totalDiffValue < 0 ? Colors.red.shade800 : (entry.totalDiffValue > 0 ? Colors.blue.shade800 : Colors.grey.shade700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari nama produk, barcode, atau kode internal...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  onChanged: (val) => controller.searchQuery.value = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Obx(() {
              return Row(
                children: [
                  _buildFilterTab('Semua', 'all', theme),
                  const SizedBox(width: 6),
                  _buildFilterTab('Belum Dihitung', 'uncounted', theme),
                  const SizedBox(width: 6),
                  _buildFilterTab('Sudah Dihitung', 'counted', theme),
                  const SizedBox(width: 6),
                  _buildFilterTab('Ada Selisih', 'diff', theme),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, String value, ThemeData theme) {
    final isSelected = controller.filterStatus.value == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => controller.filterStatus.value = value,
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
      ),
    );
  }

  Widget _buildItemsList(
    BuildContext context,
    ThemeData theme,
    OpnameDetailEntry entry,
    bool isMobile,
  ) {
    final items = controller.filteredItems;

    if (items.isEmpty) {
      if (entry.items.isEmpty) {
        return EmptyState(
          title: 'Belum Ada Produk Ditambahkan',
          message: 'Pilih "Muat Semua Produk Aktif", scan barcode, atau cari produk untuk mulai menghitung stok fisik.',
          icon: Icons.inventory_2_outlined,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.select_all),
                label: const Text('Muat Semua Produk'),
                onPressed: controller.loadAllActiveProducts,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Pilih Produk'),
                onPressed: () => _showProductSearchDialog(context),
              ),
            ],
          ),
        );
      }

      return const EmptyState(
        title: 'Tidak Ada Produk yang Cocok',
        message: 'Coba ubah kata kunci pencarian atau tab filter.',
        icon: Icons.filter_alt_off_outlined,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: 8,
      ),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemRowCard(context, theme, item, entry.isDraft, isMobile);
      },
    );
  }

  Widget _buildItemRowCard(
    BuildContext context,
    ThemeData theme,
    OpnameItemWithProduct item,
    bool isDraft,
    bool isMobile,
  ) {
    final isCounted = item.isCounted;
    final diff = item.difference;
    final hasDiff = isCounted && diff != 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: hasDiff
              ? Colors.red.shade300
              : (isCounted ? Colors.green.shade200 : theme.colorScheme.outlineVariant),
          width: hasDiff ? 1.2 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Nama Produk, Satuan & Hapus
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (item.categoryName != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.categoryName!,
                                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (item.unitName != null) ...[
                            Text(
                              'Satuan: ${item.unitName}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (item.product.barcode != null && item.product.barcode!.isNotEmpty)
                            Text(
                              'Kode: ${item.product.barcode}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isDraft)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    tooltip: 'Hapus dari daftar',
                    onPressed: () => controller.removeItem(item),
                  ),
              ],
            ),
            const Divider(height: 16),

            // Row 2: Perbandingan Stok Sistem vs Hitungan Fisik vs Selisih
            Row(
              children: [
                // Stok Sistem
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sistem', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      '${item.systemQty}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(width: 24),

                // Hitungan Fisik (Stepper jika draft)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fisik', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      if (isDraft)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 22),
                              color: isCounted && item.countedQty > 0 ? Colors.red.shade700 : Colors.grey,
                              onPressed: isCounted && item.countedQty > 0
                                  ? () => controller.decrementCount(item)
                                  : null,
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _showCountInputDialog(context, item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isCounted ? theme.colorScheme.primaryContainer : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isCounted ? theme.colorScheme.primary : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  isCounted ? '${item.countedQty}' : 'Belum dihitung',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isCounted ? theme.colorScheme.onPrimaryContainer : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 22, color: Colors.blue),
                              onPressed: () => controller.incrementCount(item),
                            ),
                          ],
                        )
                      else
                        Text(
                          isCounted ? '${item.countedQty}' : 'Tidak dihitung',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isCounted ? null : Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),

                // Selisih
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Selisih', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    if (!isCounted)
                      const Text('-', style: TextStyle(fontSize: 14, color: Colors.grey))
                    else if (diff == 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: const Text('Pas (0)', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: diff < 0 ? Colors.red.shade50 : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: diff < 0 ? Colors.red.shade300 : Colors.blue.shade300),
                        ),
                        child: Text(
                          diff > 0 ? '+$diff' : '$diff',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: diff < 0 ? Colors.red.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    if (controller.canViewCost && isCounted && diff != 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        formatRupiah(item.differenceValue),
                        style: TextStyle(
                          fontSize: 11,
                          color: diff < 0 ? Colors.red.shade700 : Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomFinalizeBar(
    BuildContext context,
    ThemeData theme,
    OpnameDetailEntry entry,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.countedCount} dari ${entry.totalItems} Produk Dihitung',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  entry.diffCount > 0 ? '${entry.diffCount} produk memiliki selisih' : 'Belum ada selisih',
                  style: TextStyle(
                    fontSize: 12,
                    color: entry.diffCount > 0 ? Colors.orange.shade800 : Colors.teal.shade800,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Review & Finalisasi'),
            onPressed: () => _showReviewModal(context),
          ),
        ],
      ),
    );
  }

  /// Dialog Review Selisih sebelum Finalisasi
  void _showReviewModal(BuildContext context) async {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    // Recalculate review
    final refreshed = await controller.prepareReview();
    if (refreshed == null) return;

    final treatAsZero = false.obs;
    final noteController = TextEditingController(text: refreshed.opname.note ?? '');

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Sheet
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined, color: Colors.teal, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Review Hasil Stock Opname',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Peringatan: Hentikan penjualan
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Peringatan: Hentikan penjualan selama menghitung agar hasil akurat.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Opsi: Anggap tidak dihitung = 0
              Obx(() {
                return Container(
                  decoration: BoxDecoration(
                    color: treatAsZero.value ? Colors.red.shade50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: treatAsZero.value ? Colors.red.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: CheckboxListTile(
                    title: const Text(
                      'Anggap produk yang belum dihitung = 0 (habis)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Jika dicentang, seluruh produk yang belum dihitung akan disesuaikan menjadi 0 stok fisiknya.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: treatAsZero.value,
                    onChanged: (val) async {
                      if (val == true) {
                        final confirm = await Get.dialog<bool>(
                          AlertDialog(
                            title: const Text('Konfirmasi Stok 0'),
                            content: const Text(
                              'PERINGATAN KERAS:\nAnda akan menganggap semua barang yang belum dihitung sebagai STOK KOSONG (0).\n\nLangkah ini akan memotong stok sistem produk tersebut menjadi 0.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Get.back(result: false),
                                child: const Text('Batal'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Get.back(result: true),
                                child: const Text('Ya, Anggap 0'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          treatAsZero.value = true;
                        }
                      } else {
                        treatAsZero.value = false;
                      }
                    },
                  ),
                );
              }),
              const SizedBox(height: 12),

              // Tabel Selisih
              const Text('Rincian Selisih Stok Terkini:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Expanded(
                child: Obx(() {
                  final asZero = treatAsZero.value;
                  final items = refreshed.items;

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      final effectiveCounted = item.isCounted ? item.countedQty : (asZero ? 0 : null);
                      final diff = effectiveCounted != null ? effectiveCounted - item.systemQty : 0;
                      final hasDiff = effectiveCounted != null && diff != 0;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          effectiveCounted != null
                              ? 'Sistem: ${item.systemQty} → Fisik: $effectiveCounted (Selisih: ${diff > 0 ? "+$diff" : "$diff"})'
                              : 'Sistem: ${item.systemQty} → Belum dihitung (Dilewati, tidak diubah)',
                          style: TextStyle(
                            fontSize: 12,
                            color: effectiveCounted == null
                                ? Colors.grey
                                : (hasDiff ? (diff < 0 ? Colors.red : Colors.blue) : Colors.green),
                          ),
                        ),
                        trailing: controller.canViewCost && effectiveCounted != null && diff != 0
                            ? Text(
                                formatRupiah(diff * item.product.costPrice),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: diff < 0 ? Colors.red : Colors.blue,
                                ),
                              )
                            : null,
                      );
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),

              // Catatan Opname
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Catatan Finalisasi (opsional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Tombol Konfirmasi
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      child: const Text('Kembali Hitung'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Obx(() {
                      return FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: controller.isSaving.value
                            ? null
                            : () async {
                                final success = await controller.executeFinalize(
                                  treatUncountedAsZero: treatAsZero.value,
                                  note: noteController.text,
                                );
                                if (success) {
                                  Get.back();
                                }
                              },
                        child: controller.isSaving.value
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Konfirmasi & Finalisasi'),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _showCountInputDialog(BuildContext context, OpnameItemWithProduct item) {
    final textController = TextEditingController(
      text: item.isCounted ? '${item.countedQty}' : '0',
    );

    Get.dialog(
      AlertDialog(
        title: Text('Hitung: ${item.product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok Sistem: ${item.systemQty} ${item.unitName ?? ""}'),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Jumlah Hitungan Fisik',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(textController.text.trim());
              if (val != null && val >= 0) {
                Get.back();
                controller.setCountDirectly(item, val);
              } else {
                Get.snackbar('Input Tidak Valid', 'Jumlah harus angka bulat >= 0');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showCategoryPickerDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Muat Produk Per Kategori'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: controller.categories.length,
            itemBuilder: (context, idx) {
              final cat = controller.categories[idx];
              return ListTile(
                title: Text(cat.name),
                onTap: () {
                  Get.back();
                  controller.loadProductsByCategory(cat.id);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showProductSearchDialog(BuildContext context) {
    final searchCtrl = TextEditingController();
    final filtered = <Product>[...controller.allProducts].obs;

    Get.dialog(
      AlertDialog(
        title: const Text('Pilih Produk untuk Dihitung'),
        content: SizedBox(
          width: 440,
          height: 400,
          child: Column(
            children: [
              TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Cari nama atau barcode...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (q) {
                  final query = q.trim().toLowerCase();
                  if (query.isEmpty) {
                    filtered.assignAll(controller.allProducts);
                  } else {
                    filtered.assignAll(
                      controller.allProducts.where((p) {
                        return p.name.toLowerCase().contains(query) ||
                            (p.barcode?.toLowerCase().contains(query) ?? false) ||
                            (p.internalCode?.toLowerCase().contains(query) ?? false);
                      }),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Obx(() {
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Tidak ada produk yang cocok'));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final p = filtered[idx];
                      return ListTile(
                        dense: true,
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Stok: ${p.currentStock} | Barcode: ${p.barcode ?? "-"}'),
                        trailing: const Icon(Icons.add, color: Colors.blue),
                        onTap: () {
                          Get.back();
                          controller.addProduct(p);
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
