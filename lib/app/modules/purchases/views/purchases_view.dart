import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/purchase_dao.dart';
import '../../../routes/app_pages.dart';
import '../controllers/purchases_controller.dart';

class PurchasesView extends GetView<PurchasesController> {
  const PurchasesView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pembelian Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: () => controller.loadPurchases(refresh: true),
          ),
          if (controller.canPurchase)
            FilledButton.icon(
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Pembelian Baru'),
              onPressed: () => Get.toNamed(Routes.PURCHASE_FORM),
            ).paddingOnly(right: 16),
        ],
      ),
      floatingActionButton: isMobile && controller.canPurchase
          ? FloatingActionButton.extended(
              onPressed: () => Get.toNamed(Routes.PURCHASE_FORM),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Pembelian'),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ringkasan Agregat Atas
              _buildTopSummary(context, theme),

              // Filter Bar
              _buildFilterBar(context, theme),

              const Divider(height: 1),

              // List Pembelian dengan Grup Harian & Pagination
              Expanded(
                child: Obx(() {
                  if (controller.isLoading.value) {
                    return const LoadingIndicator(message: 'Memuat data pembelian...');
                  }

                  if (controller.purchases.isEmpty) {
                    return EmptyState(
                      title: 'Belum Ada Transaksi Pembelian',
                      message: controller.searchQuery.value.isEmpty
                          ? 'Belum ada pencatatan pembelian atau penerimaan barang masuk.'
                          : 'Tidak ada transaksi pembelian yang cocok dengan filter aktif.',
                      icon: Icons.inventory_outlined,
                      action: controller.canPurchase
                          ? FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Buat Pembelian Baru'),
                              onPressed: () => Get.toNamed(Routes.PURCHASE_FORM),
                            )
                          : null,
                    );
                  }

                  final grouped = controller.groupedPurchases;
                  final dateKeys = grouped.keys.toList();

                  return NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                        controller.loadMore();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: 12,
                      ),
                      itemCount: dateKeys.length + (controller.hasMore.value ? 1 : 0),
                      itemBuilder: (context, idx) {
                        if (idx >= dateKeys.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final dateKey = dateKeys[idx];
                        final itemsForDay = grouped[dateKey]!;
                        return _buildDailyGroup(context, theme, dateKey, itemsForDay);
                      },
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSummary(BuildContext context, ThemeData theme) {
    return Obx(() {
      final count = controller.totalCompletedCount;
      final amount = controller.totalCompletedAmount;

      return Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: Icon(Icons.receipt_long, color: theme.colorScheme.onPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Pembelian Selesai (Diterima):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    formatRupiah(amount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count Transaksi',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildFilterBar(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris 1: Date Range Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Obx(() => Row(
                  children: [
                    _buildDateChip('Semua', PurchaseDateFilter.all),
                    _buildDateChip('Hari Ini', PurchaseDateFilter.today),
                    _buildDateChip('Kemarin', PurchaseDateFilter.yesterday),
                    _buildDateChip('7 Hari', PurchaseDateFilter.last7Days),
                    _buildDateChip('Bulan Ini', PurchaseDateFilter.thisMonth),
                    _buildCustomDateChip(context),
                  ],
                )),
          ),
          const SizedBox(height: 8),

          // Baris 2: Supplier & Status & Search
          Row(
            children: [
              // Supplier Dropdown
              Expanded(
                flex: 2,
                child: Obx(() {
                  return DropdownButtonFormField<int?>(
                    initialValue: controller.selectedSupplierId.value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pemasok',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Semua Pemasok', overflow: TextOverflow.ellipsis),
                      ),
                      ...controller.suppliers.map((s) => DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(s.name, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: controller.setSupplierFilter,
                  );
                }),
              ),
              const SizedBox(width: 8),

              // Status Dropdown
              Expanded(
                flex: 2,
                child: Obx(() {
                  return DropdownButtonFormField<String>(
                    initialValue: controller.selectedStatus.value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Semua Status')),
                      DropdownMenuItem(value: 'received', child: Text('Diterima')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
                    ],
                    onChanged: (val) => controller.setStatusFilter(val ?? 'all'),
                  );
                }),
              ),
              const SizedBox(width: 8),

              // Search Textfield
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller.searchController,
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Cari no. faktur / ref...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: Obx(() => controller.searchQuery.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              controller.searchController.clear();
                              controller.onSearchChanged('');
                            },
                          )
                        : const SizedBox.shrink()),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, PurchaseDateFilter filter) {
    final isSelected = controller.selectedDateFilter.value == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (_) => controller.setDateFilter(filter),
      ),
    );
  }

  Widget _buildCustomDateChip(BuildContext context) {
    final isSelected = controller.selectedDateFilter.value == PurchaseDateFilter.custom;
    String label = 'Kustom';
    if (isSelected && controller.customStartDate.value != null && controller.customEndDate.value != null) {
      label = '${DateFormat('dd/MM').format(controller.customStartDate.value!)} - ${DateFormat('dd/MM').format(controller.customEndDate.value!)}';
    }

    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
          initialDateRange: controller.customStartDate.value != null && controller.customEndDate.value != null
              ? DateTimeRange(start: controller.customStartDate.value!, end: controller.customEndDate.value!)
              : DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
        );
        if (picked != null) {
          controller.setDateFilter(PurchaseDateFilter.custom, start: picked.start, end: picked.end);
        }
      },
    );
  }

  Widget _buildDailyGroup(
    BuildContext context,
    ThemeData theme,
    String dateKey,
    List<PurchaseWithSupplier> items,
  ) {
    final parsedDate = DateTime.tryParse(dateKey) ?? DateTime.now();
    final headerDateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(parsedDate);
    final dailyTotal = items
        .where((p) => p.purchase.status == 'received')
        .fold<int>(0, (sum, p) => sum + p.purchase.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Daily Group Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    headerDateStr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Text(
                'Total: ${formatRupiah(dailyTotal)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        // Items in this day
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final entry = items[i];
              return _buildPurchaseTile(context, theme, entry);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseTile(BuildContext context, ThemeData theme, PurchaseWithSupplier item) {
    final p = item.purchase;
    final isCancelled = p.status == 'cancelled';
    final timeStr = DateFormat('HH:mm').format(p.date.toLocal());

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: isCancelled
            ? Colors.red.withValues(alpha: 0.15)
            : theme.colorScheme.primaryContainer,
        child: Icon(
          isCancelled ? Icons.cancel_outlined : Icons.inventory_2_outlined,
          color: isCancelled ? Colors.red : theme.colorScheme.primary,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              p.refNo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
                color: isCancelled ? Colors.grey : null,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isCancelled ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isCancelled ? Colors.red.shade300 : Colors.green.shade300),
            ),
            child: Text(
              isCancelled ? 'Dibatalkan' : 'Diterima',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isCancelled ? Colors.red.shade800 : Colors.green.shade800,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.business, size: 13, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.supplierName,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatRupiah(p.total),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isCancelled ? Colors.grey : theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showPurchaseDetailDialog(context, theme, p.id),
    );
  }

  Future<void> _showPurchaseDetailDialog(BuildContext context, ThemeData theme, int purchaseId) async {
    final detail = await controller.getPurchaseDetail(purchaseId);
    if (detail == null) {
      Get.snackbar('Error', 'Detail pembelian tidak ditemukan.');
      return;
    }

    final p = detail.purchase;
    final isCancelled = p.status == 'cancelled';
    final formattedDate = DateFormat('EEEE, dd MMMM yyyy HH:mm', 'id_ID').format(p.date.toLocal());

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isCancelled ? Colors.red.shade100 : theme.colorScheme.primaryContainer,
                      child: Icon(
                        isCancelled ? Icons.cancel_outlined : Icons.receipt_long,
                        color: isCancelled ? Colors.red : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.refNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('Pemasok: ${detail.supplierName}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Waktu: $formattedDate', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 16),

                // Table Items
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Daftar Barang Masuk:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        ...detail.items.map((it) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text(
                                        '${it.item.qty} x ${formatRupiah(it.item.costPrice)}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatRupiah(it.subtotal),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 16),

                // Total Summary
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Pembelian:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      formatRupiah(p.total),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isCancelled ? Colors.grey : theme.colorScheme.primary,
                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!isCancelled && controller.canPurchase)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                        label: const Text('Batalkan Pembelian', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                        onPressed: () {
                          Get.back();
                          _showCancelPurchaseDialog(context, p);
                        },
                      )
                    else
                      const SizedBox.shrink(),
                    FilledButton(
                      onPressed: () => Get.back(),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCancelPurchaseDialog(BuildContext context, Purchase purchase) {
    final reasonController = TextEditingController();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.red.shade100,
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Batalkan Pembelian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(purchase.refNo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Perhatian: Pembatalan akan mengembalikan stok produk (mengurangi stok yang sebelumnya masuk). Jika stok fisik saat ini tidak mencukupi, pembatalan akan ditolak.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Alasan Pembatalan (Wajib, min 5 karakter) *',
                    hintText: 'Misal: Salah input faktur / retur langsung',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        final reason = reasonController.text.trim();
                        if (reason.length < 5) {
                          Get.snackbar('Validasi Gagal', 'Alasan pembatalan wajib diisi minimal 5 karakter');
                          return;
                        }
                        final success = await controller.cancelPurchase(
                          purchaseId: purchase.id,
                          reason: reason,
                        );
                        if (success) {
                          Get.back();
                        }
                      },
                      child: const Text('Ya, Batalkan Pembelian'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
