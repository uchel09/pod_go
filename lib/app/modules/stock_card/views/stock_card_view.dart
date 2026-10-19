import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/daos/stock_dao.dart';
import '../controllers/stock_card_controller.dart';

class StockCardView extends GetView<StockCardController> {
  const StockCardView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kartu Stok'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Segarkan',
            icon: const Icon(Icons.refresh),
            onPressed: controller.loadInitialData,
          ),
        ],
      ),
      body: Obx(() {
        if (!controller.canViewStock) {
          return const ErrorState(
            title: 'Akses Ditolak',
            message: 'Anda tidak memiliki hak akses untuk melihat kartu stok (stock.view).',
            icon: Icons.lock_outline,
          );
        }

        return Column(
          children: [
            _buildFilterHeader(context, theme),
            const Divider(height: 1),
            if (controller.isPerProductMode && controller.selectedProduct.value != null)
              _buildProductHeaderCard(context, theme),
            Expanded(
              child: _buildStockContent(context, theme),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildFilterHeader(BuildContext context, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris 1: Pencarian
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari produk atau catatan mutasi...',
                    hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: controller.searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: controller.clearSearch,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onSubmitted: controller.onSearchSubmitted,
                  onChanged: (val) {
                    if (val.isEmpty && controller.searchQuery.value.isNotEmpty) {
                      controller.clearSearch();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => controller.onSearchSubmitted(controller.searchController.text),
                child: const Text('Cari', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              if (controller.selectedProductId.value != null ||
                  controller.selectedType.value != 'all' ||
                  controller.selectedDateFilter.value != 'all' ||
                  controller.searchQuery.value.isNotEmpty) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Reset Semua Filter',
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  onPressed: controller.clearAllFilters,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Baris 2: Filter Horizontal (Mode Produk, Tipe Mutasi, Rentang Tanggal)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Dropdown Pilih Produk (Global vs Per-Produk)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: controller.selectedProductId.value,
                      hint: const Text('Mode: Global (Semua Produk)', style: TextStyle(fontSize: 12)),
                      isDense: true,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('🌐 Mode Global (Semua Produk)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        ...controller.products.map(
                          (p) => DropdownMenuItem<int?>(
                            value: p.id,
                            child: Text(p.name, style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                      onChanged: (val) => controller.setProductFilter(val),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(height: 20, width: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(width: 8),

                // Filter Tipe Mutasi
                _buildChip(
                  label: 'Semua Tipe',
                  isSelected: controller.selectedType.value == 'all',
                  onSelected: () => controller.setTypeFilter('all'),
                  theme: theme,
                ),
                _buildChip(
                  label: 'Penjualan',
                  isSelected: controller.selectedType.value == 'sale',
                  onSelected: () => controller.setTypeFilter('sale'),
                  theme: theme,
                  selectedColor: Colors.red.shade700,
                ),
                _buildChip(
                  label: 'Pembelian',
                  isSelected: controller.selectedType.value == 'purchase',
                  onSelected: () => controller.setTypeFilter('purchase'),
                  theme: theme,
                  selectedColor: Colors.green.shade700,
                ),
                _buildChip(
                  label: 'Penyesuaian',
                  isSelected: controller.selectedType.value == 'adjustment',
                  onSelected: () => controller.setTypeFilter('adjustment'),
                  theme: theme,
                  selectedColor: Colors.orange.shade800,
                ),
                _buildChip(
                  label: 'Opname',
                  isSelected: controller.selectedType.value == 'opname',
                  onSelected: () => controller.setTypeFilter('opname'),
                  theme: theme,
                  selectedColor: Colors.blue.shade700,
                ),
                _buildChip(
                  label: 'Void',
                  isSelected: controller.selectedType.value == 'void',
                  onSelected: () => controller.setTypeFilter('void'),
                  theme: theme,
                  selectedColor: Colors.purple.shade700,
                ),

                const SizedBox(width: 8),
                Container(height: 20, width: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(width: 8),

                // Filter Tanggal
                _buildChip(
                  label: 'Semua Waktu',
                  isSelected: controller.selectedDateFilter.value == 'all',
                  onSelected: () => controller.setDateFilter('all'),
                  theme: theme,
                ),
                _buildChip(
                  label: 'Hari Ini',
                  isSelected: controller.selectedDateFilter.value == 'today',
                  onSelected: () => controller.setDateFilter('today'),
                  theme: theme,
                ),
                _buildChip(
                  label: 'Kemarin',
                  isSelected: controller.selectedDateFilter.value == 'yesterday',
                  onSelected: () => controller.setDateFilter('yesterday'),
                  theme: theme,
                ),
                _buildChip(
                  label: '7 Hari',
                  isSelected: controller.selectedDateFilter.value == '7days',
                  onSelected: () => controller.setDateFilter('7days'),
                  theme: theme,
                ),
                _buildChip(
                  label: 'Bulan Ini',
                  isSelected: controller.selectedDateFilter.value == 'month',
                  onSelected: () => controller.setDateFilter('month'),
                  theme: theme,
                ),
                _buildChip(
                  label: controller.selectedDateFilter.value == 'custom' && controller.customDateRange.value != null
                      ? '${DateFormat('dd/MM').format(controller.customDateRange.value!.start)} - ${DateFormat('dd/MM').format(controller.customDateRange.value!.end)}'
                      : 'Kustom Tanggal',
                  icon: Icons.calendar_month_outlined,
                  isSelected: controller.selectedDateFilter.value == 'custom',
                  onSelected: () async {
                    final initial = controller.customDateRange.value ??
                        DateTimeRange(
                          start: DateTime.now().subtract(const Duration(days: 7)),
                          end: DateTime.now(),
                        );
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      controller.setDateFilter('custom', customRange: picked);
                    }
                  },
                  theme: theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    required ThemeData theme,
    IconData? icon,
    Color? selectedColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: icon != null ? Icon(icon, size: 14, color: isSelected ? Colors.white : theme.colorScheme.primary) : null,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        selectedColor: selectedColor ?? theme.colorScheme.primary,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildProductHeaderCard(BuildContext context, ThemeData theme) {
    final product = controller.selectedProduct.value!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Barcode: ${product.barcode ?? product.internalCode ?? "-"} | Min Stok: ${product.minStock}',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Stok Saat Ini', style: TextStyle(fontSize: 10, color: Colors.white70)),
                Text(
                  '${product.currentStock}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockContent(BuildContext context, ThemeData theme) {
    if (controller.isLoading.value) {
      return const Center(child: LoadingIndicator(message: 'Memuat mutasi kartu stok...'));
    }

    if (controller.entries.isEmpty) {
      return const EmptyState(
        title: 'Belum Ada Mutasi',
        message: 'Tidak ditemukan riwayat mutasi stok untuk filter yang dipilih.',
        icon: Icons.table_chart_outlined,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;

        return ListView.builder(
          controller: controller.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: controller.entries.length + (controller.isLoadingMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == controller.entries.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final entry = controller.entries[index];
            return isDesktop
                ? _buildDesktopMovementCard(context, theme, entry)
                : _buildMobileMovementCard(context, theme, entry);
          },
        );
      },
    );
  }

  Widget _buildDesktopMovementCard(BuildContext context, ThemeData theme, StockCardEntry entry) {
    final isPositive = entry.qtyChange > 0;
    final qtyStr = isPositive ? '+${entry.qtyChange}' : '${entry.qtyChange}';
    final formattedTime = DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt.toLocal());
    final typeBadge = _buildTypeBadge(entry.type);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Waktu
            SizedBox(
              width: 120,
              child: Text(
                formattedTime,
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
              ),
            ),
            // Produk (Jika mode global)
            if (!controller.isPerProductMode) ...[
              Expanded(
                flex: 3,
                child: Text(
                  entry.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Tipe Mutasi Badge
            SizedBox(width: 100, child: typeBadge),
            const SizedBox(width: 8),
            // Perubahan Stok (+/-)
            SizedBox(
              width: 70,
              child: Text(
                qtyStr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Saldo Sesudah (Running Balance)
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Saldo: ${entry.stockAfter}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            // Referensi (Clickable if Sale)
            SizedBox(
              width: 110,
              child: _buildReferenceWidget(context, theme, entry),
            ),
            const SizedBox(width: 8),
            // Catatan
            Expanded(
              flex: 3,
              child: Text(
                entry.note ?? '-',
                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Kasir / User
            SizedBox(
              width: 90,
              child: Text(
                entry.userName,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMovementCard(BuildContext context, ThemeData theme, StockCardEntry entry) {
    final isPositive = entry.qtyChange > 0;
    final qtyStr = isPositive ? '+${entry.qtyChange}' : '${entry.qtyChange}';
    final formattedTime = DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt.toLocal());

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!controller.isPerProductMode)
                  Expanded(
                    child: Text(
                      entry.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(formattedTime, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                _buildTypeBadge(entry.type),
              ],
            ),
            if (!controller.isPerProductMode) ...[
              const SizedBox(height: 4),
              Text(formattedTime, style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.grey)),
            ],
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Mutasi: ',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                    ),
                    Text(
                      qtyStr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Saldo: ${entry.stockAfter}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildReferenceWidget(context, theme, entry),
                Text('User: ${entry.userName}', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
              ],
            ),
            if (entry.note != null && entry.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Catatan: ${entry.note}',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bg;
    Color fg;
    String label;

    switch (type) {
      case 'sale':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        label = 'Penjualan';
        break;
      case 'purchase':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = 'Pembelian';
        break;
      case 'adjustment':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'Penyesuaian';
        break;
      case 'opname':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        label = 'Opname';
        break;
      case 'void':
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        label = 'Void';
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade800;
        label = type;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg),
        ),
      ),
    );
  }

  Widget _buildReferenceWidget(BuildContext context, ThemeData theme, StockCardEntry entry) {
    if (entry.refTable == null && entry.refId == null) {
      return Text('-', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline));
    }

    final isSale = entry.refTable == 'sales' || entry.refTable == 'sale';
    final refText = isSale ? 'Penjualan #${entry.refId}' : '${entry.refTable ?? "Ref"} #${entry.refId ?? ""}';

    if (isSale && entry.refId != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _openSaleDetailDialog(context, theme, entry.refId!),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              refText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      refText,
      style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
    );
  }

  void _openSaleDetailDialog(BuildContext context, ThemeData theme, int saleId) async {
    final detail = await controller.getSaleDetail(saleId);
    if (detail == null) {
      Get.snackbar('Informasi', 'Detail transaksi #$saleId tidak ditemukan');
      return;
    }

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      detail.sale.invoiceNo,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                Text(
                  'Kasir: ${detail.cashierName} • ${DateFormat("dd/MM/yyyy HH:mm").format(detail.sale.createdAt.toLocal())}',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                ),
                const Divider(height: 16),
                const Text('Item Transaksi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...detail.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.qty}x ${item.productName}',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(formatRupiah(item.subtotal), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(formatRupiah(detail.sale.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Get.back(),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
