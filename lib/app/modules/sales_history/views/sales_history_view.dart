import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/sale_return_dao.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../routes/app_pages.dart';
import '../controllers/sales_history_controller.dart';

class SalesHistoryView extends GetView<SalesHistoryController> {
  const SalesHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        actions: [
          IconButton(
            tooltip: 'Segarkan Data',
            icon: const Icon(Icons.refresh),
            onPressed: controller.loadInitialData,
          ),
        ],
      ),
      body: Obx(() {
        if (!controller.canViewHistory) {
          return const Center(
            child: ErrorState(
              title: 'Akses Ditolak',
              message:
                  'Anda tidak memiliki hak akses untuk melihat riwayat penjualan (pos.sell atau pos.void).',
              icon: Icons.lock_outline,
            ),
          );
        }

        return Column(
          children: [
            // Tab Pemilih: Penjualan vs Riwayat Retur
            _buildTabSelector(context, theme),

            // Panel Filter & Pencarian
            _buildFilterHeader(context, theme),

            // Ringkasan Total di Atas List (hanya tampil di tab Penjualan)
            if (controller.currentTab.value == 0)
              _buildAggregateSummaryCard(context, theme),

            // Konten Riwayat
            Expanded(
              child: controller.currentTab.value == 0
                  ? _buildHistoryContent(context, theme)
                  : _buildReturnsContent(context, theme),
            ),
          ],
        );
      }),
    );
  }

  /// Tab Switcher Penjualan vs Riwayat Retur
  Widget _buildTabSelector(BuildContext context, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Obx(() => SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Transaksi Penjualan'),
                icon: Icon(Icons.point_of_sale),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Riwayat Retur'),
                icon: Icon(Icons.assignment_return),
              ),
            ],
            selected: {controller.currentTab.value},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                controller.currentTab.value = set.first;
                if (set.first == 1) {
                  controller.fetchReturns();
                }
              }
            },
          )),
    );
  }

  /// Panel Pencarian & Filter (Tanggal dan Status)
  Widget _buildFilterHeader(BuildContext context, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris Input Cari Invoice
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nomor invoice (mis: INV-...)',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: controller.searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: controller.clearSearch,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: controller.onSearchSubmitted,
                  onChanged: (val) {
                    if (val.isEmpty &&
                        controller.searchQuery.value.isNotEmpty) {
                      controller.clearSearch();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => controller.onSearchSubmitted(
                  controller.searchController.text,
                ),
                child: const Text(
                  'Cari',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (controller.selectedDateFilter.value != 'all' ||
                  controller.selectedStatusFilter.value != 'all' ||
                  controller.selectedCashierId.value != null ||
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

          // Baris Chips Filter Tanggal, Status & Kasir
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Filter Tanggal
                _buildFilterChip(
                  label: 'Semua Waktu',
                  isSelected: controller.selectedDateFilter.value == 'all',
                  onSelected: (_) => controller.setDateFilter('all'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label: 'Hari Ini',
                  isSelected: controller.selectedDateFilter.value == 'today',
                  onSelected: (_) => controller.setDateFilter('today'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label: 'Kemarin',
                  isSelected:
                      controller.selectedDateFilter.value == 'yesterday',
                  onSelected: (_) => controller.setDateFilter('yesterday'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label: '7 Hari',
                  isSelected: controller.selectedDateFilter.value == '7days',
                  onSelected: (_) => controller.setDateFilter('7days'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label: 'Bulan Ini',
                  isSelected: controller.selectedDateFilter.value == 'month',
                  onSelected: (_) => controller.setDateFilter('month'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label:
                      controller.selectedDateFilter.value == 'custom' &&
                          controller.customDateRange.value != null
                      ? '${DateFormat('dd/MM').format(controller.customDateRange.value!.start)} - ${DateFormat('dd/MM').format(controller.customDateRange.value!.end)}'
                      : 'Kustom Tanggal',
                  icon: Icons.calendar_month_outlined,
                  isSelected: controller.selectedDateFilter.value == 'custom',
                  onSelected: (_) async {
                    final initial =
                        controller.customDateRange.value ??
                        DateTimeRange(
                          start: DateTime.now().subtract(
                            const Duration(days: 7),
                          ),
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

                const SizedBox(width: 8),
                Container(
                  height: 20,
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: 8),

                // Filter Status Transaksi
                _buildFilterChip(
                  label: 'Semua Status',
                  isSelected: controller.selectedStatusFilter.value == 'all',
                  onSelected: (_) => controller.setStatusFilter('all'),
                  theme: theme,
                ),
                _buildFilterChip(
                  label: 'Selesai',
                  isSelected:
                      controller.selectedStatusFilter.value == 'completed',
                  onSelected: (_) => controller.setStatusFilter('completed'),
                  theme: theme,
                  selectedColor: Colors.green.shade700,
                ),
                _buildFilterChip(
                  label: 'VOID',
                  isSelected: controller.selectedStatusFilter.value == 'void',
                  onSelected: (_) => controller.setStatusFilter('void'),
                  theme: theme,
                  selectedColor: Colors.red.shade700,
                ),

                // Filter Kasir (Hanya tampil jika bukan mode Solo dan pengguna memiliki izin pos.view_all_sales)
                if (!controller.isSoloMode && controller.canViewAllSales) ...[
                  const SizedBox(width: 8),
                  Container(
                    height: 20,
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Semua Kasir',
                    isSelected: controller.selectedCashierId.value == null,
                    onSelected: (_) => controller.setCashierFilter(null),
                    theme: theme,
                  ),
                  for (final cashier in controller.cashiers)
                    _buildFilterChip(
                      label: cashier.displayName,
                      icon: Icons.person_outline,
                      isSelected:
                          controller.selectedCashierId.value == cashier.id,
                      onSelected: (_) =>
                          controller.setCashierFilter(cashier.id),
                      theme: theme,
                      selectedColor: theme.colorScheme.tertiary,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
    required ThemeData theme,
    IconData? icon,
    Color? selectedColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: icon != null
            ? Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : theme.colorScheme.primary,
              )
            : null,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: onSelected,
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

  /// Ringkasan Total di Atas List (Omzet & Jumlah Transaksi, VOID tidak dihitung)
  Widget _buildAggregateSummaryCard(BuildContext context, ThemeData theme) {
    final agg = controller.aggregateSummary.value;
    final txCount = agg?.transactionCount ?? 0;
    final totalRevenue = agg?.totalRevenue ?? 0;
    final selectedCashierId = controller.selectedCashierId.value;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.15,
                ),
                child: Icon(
                  Icons.query_stats_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$txCount Transaksi',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (selectedCashierId != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Ringkasan Kasir: ${controller.selectedCashierName}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    'Void tidak dihitung omzet',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Total Omzet Bersih',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                formatRupiah(totalRevenue),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Konten List Grup Riwayat
  Widget _buildHistoryContent(BuildContext context, ThemeData theme) {
    if (controller.isLoading.value) {
      return const Center(
        child: LoadingIndicator(message: 'Memuat riwayat transaksi...'),
      );
    }

    final groups = controller.groupedSales;
    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadInitialData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child: EmptyState(
                title: 'Tidak Ada Transaksi',
                message:
                    'Tidak ditemukan transaksi yang cocok dengan filter atau pencarian.',
                icon: Icons.receipt_long_outlined,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadInitialData,
      child: ListView.builder(
        controller: controller.scrollController,
        padding: const EdgeInsets.only(bottom: 32),
        itemCount:
            groups.keys.length + (controller.isLoadingMore.value ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= groups.keys.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final dayKey = groups.keys.elementAt(index);
          final dayEntries = groups[dayKey]!;
          final summary = controller.dailySummaries[dayKey];

          final parsedDate =
              DateTime.tryParse(dayKey) ??
              dayEntries.first.sale.createdAt.toLocal();
          final dayLabel = DateFormatter.formatFullDate(parsedDate);

          final totalRevenue =
              summary?.totalRevenue ??
              dayEntries.fold<int>(
                0,
                (sum, e) =>
                    sum + (e.sale.status == 'completed' ? e.sale.total : 0),
              );
          final completedTxCount =
              summary?.transactionCount ??
              dayEntries.where((e) => e.sale.status == 'completed').length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Tanggal & Omzet Harian
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '$completedTxCount Transaksi Selesai${dayEntries.length > completedTxCount ? ' • ${dayEntries.length - completedTxCount} Void' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Omzet Hari Ini',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          formatRupiah(totalRevenue),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Daftar Transaksi pada hari tersebut
              ...dayEntries.map(
                (entry) => _buildSaleTile(context, entry, theme),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Satu Baris Transaksi
  Widget _buildSaleTile(
    BuildContext context,
    SaleListEntry entry,
    ThemeData theme,
  ) {
    final sale = entry.sale;
    final timeStr = DateFormat('HH:mm').format(sale.createdAt.toLocal());
    final isVoid = sale.status == 'void';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isVoid
              ? Colors.red.shade200
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showSaleDetailDialog(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon Status
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isVoid
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isVoid
                      ? Icons.do_not_disturb_on_outlined
                      : Icons.receipt_long,
                  color: isVoid ? Colors.red.shade700 : Colors.green.shade800,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // Detail Invoice, Jam, Kasir
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sale.invoiceNo,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            decoration: isVoid
                                ? TextDecoration.lineThrough
                                : null,
                            color: isVoid ? Colors.grey : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        if (isVoid) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'VOID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Kasir: ${entry.cashierName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...entry.paymentMethods.map(
                          (m) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Nominal Transaksi
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(sale.total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isVoid ? Colors.red.shade400 : null,
                      decoration: isVoid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (sale.discount > 0 && !isVoid)
                    Text(
                      'Hemat ${formatRupiah(sale.discount)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog Rincian Transaksi Lengkap
  void _showSaleDetailDialog(BuildContext context, SaleListEntry entry) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: FutureBuilder<SaleDetail?>(
            future: controller.getDetail(entry.sale.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: LoadingIndicator(
                    message: 'Memuat rincian transaksi...',
                  ),
                );
              }
              final detail = snapshot.data;
              if (detail == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Data transaksi tidak ditemukan.')),
                );
              }

              final sale = detail.sale;
              final isVoid = sale.status == 'void';
              final receipt = controller.buildReceipt(detail, isReprint: true);

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Detail
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isVoid
                              ? Colors.red.shade700
                              : Colors.blueGrey,
                          child: Icon(
                            isVoid
                                ? Icons.do_not_disturb_on
                                : Icons.receipt_long,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    sale.invoiceNo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isVoid)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade700,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'VOID',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                '${DateFormatter.formatDateTime(sale.createdAt)} • Kasir: ${detail.cashierName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Get.back(),
                        ),
                      ],
                    ),

                    // Info VOID Banner
                    if (isVoid) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TRANSAKSI INI TELAH DIBATALKAN (VOID)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (sale.voidedAt != null)
                              Text(
                                'Waktu Void: ${DateFormatter.formatDateTime(sale.voidedAt!)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            if (detail.voidedByName != null)
                              Text(
                                'Dibatalkan oleh: ${detail.voidedByName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            Text(
                              'Alasan: ${sale.voidReason ?? '-'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(height: 20),

                    // Daftar Item (Snapshot)
                    Expanded(
                      child: ListView(
                        children: [
                          const Text(
                            'Item Pembelian (Snapshot)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...detail.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        Text(
                                          '${item.qty} x ${formatRupiah(item.price)}${item.discount > 0 ? ' (Disc: -${formatRupiah(item.discount)})' : ''}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    formatRupiah(item.subtotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 24),

                          // Rincian Angka Keuangan
                          _buildRow('Subtotal', formatRupiah(sale.subtotal)),
                          if (detail.items.fold<int>(0, (sum, i) => sum + (i.discount * i.qty)) > 0)
                            _buildRow(
                              'Diskon Item',
                              '-${formatRupiah(detail.items.fold<int>(0, (sum, i) => sum + (i.discount * i.qty)))}',
                              color: Colors.green.shade800,
                            ),
                          if ((sale.discount - detail.items.fold<int>(0, (sum, i) => sum + (i.discount * i.qty))) > 0)
                            _buildRow(
                              'Diskon Nota',
                              '-${formatRupiah(sale.discount - detail.items.fold<int>(0, (sum, i) => sum + (i.discount * i.qty)))}',
                              color: Colors.orange.shade800,
                            ),
                          if (sale.tax > 0)
                            _buildRow(
                              'Pajak${sale.taxRateBps != null && sale.taxRateBps! > 0 ? (sale.taxRateBps! % 100 == 0 ? ' (${sale.taxRateBps! ~/ 100}%)' : ' (${sale.taxRateBps! / 100}%)') : ''}${sale.taxMode == 'inclusive' ? ' (Inklusif)' : ''}',
                              formatRupiah(sale.tax),
                            ),
                          _buildRow(
                            'Total',
                            formatRupiah(sale.total),
                            isBold: true,
                          ),
                          const Divider(height: 16),
                          _buildRow('Dibayar', formatRupiah(sale.paid)),
                          _buildRow(
                            'Kembalian',
                            formatRupiah(sale.change),
                            color: Colors.green,
                            isBold: true,
                          ),
                          const SizedBox(height: 12),

                          // Rincian Metode Bayar
                          const Text(
                            'Metode Pembayaran',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...detail.payments.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: _buildRow(
                                '• ${p.method.toUpperCase()}',
                                formatRupiah(p.amount),
                              ),
                            ),
                          ),

                          // Riwayat Retur untuk Nota ini (jika ada)
                          FutureBuilder<List<SaleReturn>>(
                            future: controller.getReturnsForSale(sale.id),
                            builder: (context, retSnap) {
                              final returns = retSnap.data ?? [];
                              if (returns.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.assignment_return,
                                              size: 16, color: Colors.amber.shade900),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Riwayat Retur Transaksi Ini (${returns.length}):',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ...returns.map((r) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Text(
                                              '• ${r.returnNo} (${DateFormatter.formatDateTime(r.createdAt)}): -${formatRupiah(r.total)} [${r.reason}]',
                                              style: TextStyle(
                                                  fontSize: 11, color: Colors.brown.shade800),
                                            ),
                                          )),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tombol Aksi: Cetak Ulang, PDF, Retur, dan Void
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                ),
                                onPressed: () => controller.savePdf(receipt),
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  size: 18,
                                ),
                                label: const Text('Simpan PDF'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                ),
                                onPressed: () =>
                                    controller.printReceipt(receipt),
                                icon: const Icon(Icons.print, size: 18),
                                label: const Text('Cetak Salinan'),
                              ),
                            ),
                          ],
                        ),

                        // Tombol Retur (Hanya tampil jika canReturn dan status completed)
                        if (controller.canReturn && !isVoid) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber.shade900,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              onPressed: () async {
                                Get.back();
                                final res = await Get.toNamed(
                                  Routes.SALE_RETURN,
                                  arguments: sale.id,
                                );
                                if (res == true) {
                                  controller.loadInitialData();
                                  if (controller.currentTab.value == 1) {
                                    controller.fetchReturns();
                                  }
                                }
                              },
                              icon: const Icon(Icons.assignment_return, size: 18),
                              label: const Text('Retur Barang / Refund'),
                            ),
                          ),
                        ],

                        // Tombol VOID (Hanya tampil jika canVoid dan status completed)
                        if (controller.canVoid && !isVoid) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade400),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                              onPressed: () =>
                                  _showVoidConfirmDialog(context, sale),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Batalkan Transaksi (VOID)'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Dialog Konfirmasi & Input Alasan Void
  void _showVoidConfirmDialog(BuildContext context, Sale sale) {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Batalkan Transaksi (VOID)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'Tindakan ini tidak dapat diurungkan. Stok produk akan dikembalikan secara otomatis ke inventaris dan status nota ${sale.invoiceNo} menjadi VOID.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Alasan Pembatalan *',
                      hintText:
                          'Contoh: Pelanggan salah pesan / salah input nominal',
                      hintStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().length < 5) {
                        return 'Alasan wajib diisi minimal 5 karakter.';
                      }
                      return null;
                    },
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
                      Obx(
                        () => FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: controller.isVoiding.value
                              ? null
                              : () async {
                                  if (formKey.currentState!.validate()) {
                                    final success = await controller.voidSale(
                                      sale: sale,
                                      reason: reasonController.text,
                                    );
                                    if (success) {
                                      Get.back(); // Tutup dialog void
                                      Get.back(); // Tutup dialog detail
                                    }
                                  }
                                },
                          icon: controller.isVoiding.value
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: const Text('Ya, Void Transaksi'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB RIWAYAT RETUR PENJUALAN
  // ==========================================

  Widget _buildReturnsContent(BuildContext context, ThemeData theme) {
    return Obx(() {
      if (controller.isLoadingReturns.value) {
        return const Center(child: LoadingIndicator(message: 'Memuat riwayat retur...'));
      }

      final returns = controller.returnEntries;
      if (returns.isEmpty) {
        return const Center(
          child: EmptyState(
            title: 'Belum Ada Transaksi Retur',
            message: 'Tidak ada riwayat retur barang pada filter tanggal yang dipilih.',
            icon: Icons.assignment_return_outlined,
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: controller.fetchReturns,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: returns.length,
          itemBuilder: (context, index) {
            final entry = returns[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                onTap: () => _showReturnDetailDialog(context, entry),
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade100,
                  child: Icon(Icons.assignment_return, color: Colors.amber.shade900, size: 20),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.saleReturn.returnNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '-${formatRupiah(entry.saleReturn.total)}',
                      style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Nota: ${entry.invoiceNo} • ${entry.itemCount} barang • Kasir: ${entry.cashierName}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Alasan: ${entry.saleReturn.reason}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
              ),
            );
          },
        ),
      );
    });
  }

  void _showReturnDetailDialog(BuildContext context, SaleReturnEntry entry) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FutureBuilder<SaleReturnDetail?>(
            future: controller.getReturnDetail(entry.saleReturn.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: LoadingIndicator(message: 'Memuat detail retur...'),
                );
              }

              final detail = snapshot.data;
              if (detail == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Data retur tidak ditemukan.'),
                );
              }

              final ret = detail.saleReturn;
              final receipt = controller.buildReturnReceipt(detail);

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.amber.shade100,
                          child: Icon(Icons.assignment_return, color: Colors.amber.shade900),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ret.returnNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Nota Asal: ${detail.invoiceNo}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Get.back(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text('Waktu: ${DateFormatter.formatDateTime(ret.createdAt)} • Kasir: ${detail.cashierName}', style: const TextStyle(fontSize: 12)),
                    Text('Alasan: ${ret.reason}', style: const TextStyle(fontSize: 12)),
                    Text('Metode Refund: ${ret.refundMethod.toUpperCase()}', style: const TextStyle(fontSize: 12)),
                    const Divider(height: 24),
                    const Text('Rincian Barang Diretur:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...detail.items.map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    Text(
                                      '${it.qty} x ${formatRupiah(it.unitPrice)} ${it.restock ? "(Kembali ke Stok)" : "(Rusak - Tidak Restock)"}',
                                      style: TextStyle(fontSize: 11, color: it.restock ? Colors.green.shade800 : Colors.red.shade800),
                                    ),
                                  ],
                                ),
                              ),
                              Text(formatRupiah(it.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        )),
                    const Divider(height: 20),
                    _buildRow('Subtotal Retur', formatRupiah(ret.subtotal)),
                    if (ret.taxRefund > 0)
                      _buildRow('Pajak Dikembalikan', formatRupiah(ret.taxRefund)),
                    _buildRow('Total Pengembalian', formatRupiah(ret.total), isBold: true, color: Colors.red.shade800),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => controller.savePdf(receipt),
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('Simpan PDF'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade900),
                            onPressed: () => controller.printReceipt(receipt),
                            icon: const Icon(Icons.print, size: 18),
                            label: const Text('Cetak Bukti'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
