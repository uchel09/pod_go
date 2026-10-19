import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/daos/opname_dao.dart';
import '../../../routes/app_pages.dart';
import '../controllers/stock_opname_controller.dart';

class StockOpnameView extends GetView<StockOpnameController> {
  const StockOpnameView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Opname'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: () => controller.loadOpnames(refresh: true),
          ),
          if (!isMobile && controller.canManage)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: FilledButton.icon(
                icon: controller.hasFeature
                    ? const Icon(Icons.add)
                    : const Icon(Icons.lock, size: 16, color: Colors.amber),
                label: const Text('Mulai Opname Baru'),
                onPressed: controller.createNewOpname,
              ),
            ),
        ],
      ),
      floatingActionButton: isMobile && controller.canManage
          ? FloatingActionButton.extended(
              onPressed: controller.createNewOpname,
              icon: controller.hasFeature
                  ? const Icon(Icons.add)
                  : const Icon(Icons.lock, size: 16, color: Colors.amber),
              label: const Text('Mulai Opname'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Filter Bar
            _buildFilterBar(context, theme, isMobile),

            // Daftar Sesi Opname
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value && controller.opnames.isEmpty) {
                  return const LoadingIndicator(message: 'Memuat data sesi opname...');
                }

                if (controller.opnames.isEmpty) {
                  return EmptyState(
                    title: 'Belum Ada Sesi Stock Opname',
                    message: controller.searchQuery.value.isEmpty
                        ? 'Mulai sesi opname baru untuk mencocokkan stok fisik dengan sistem.'
                        : 'Tidak ada sesi opname yang cocok dengan filter pencarian.',
                    icon: Icons.checklist_rtl_outlined,
                    action: controller.canManage
                        ? FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Mulai Opname Baru'),
                            onPressed: controller.createNewOpname,
                          )
                        : null,
                  );
                }

                final grouped = controller.groupedOpnames;
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
                      vertical: 8,
                    ),
                    itemCount: dateKeys.length + (controller.hasMore.value ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= dateKeys.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator.adaptive()),
                        );
                      }

                      final dateKey = dateKeys[index];
                      final opnamesOnDay = grouped[dateKey] ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  dateKey,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${opnamesOnDay.length} sesi',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...opnamesOnDay.map((entry) => _buildOpnameCard(context, theme, entry, isMobile)),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, ThemeData theme, bool isMobile) {
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
              // Search Input
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari kode opname atau catatan...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  onChanged: controller.onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),

              // Date Range Button
              Obx(() {
                final hasDate = controller.selectedDateRange.value != null;
                return IconButton.filledTonal(
                  tooltip: hasDate ? 'Hapus Filter Tanggal' : 'Filter Tanggal',
                  icon: Icon(
                    hasDate ? Icons.event_available : Icons.date_range,
                    color: hasDate ? theme.colorScheme.primary : null,
                  ),
                  onPressed: () async {
                    if (hasDate) {
                      controller.setDateRange(null);
                    } else {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        controller.setDateRange(picked);
                      }
                    }
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 8),

          // Status Chips (Semua, Draft, Final)
          Obx(() {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusChip('Semua', 'all', theme),
                  const SizedBox(width: 8),
                  _buildStatusChip('Draft Hitung', 'draft', theme),
                  const SizedBox(width: 8),
                  _buildStatusChip('Selesai (Final)', 'final', theme),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, ThemeData theme) {
    final isSelected = controller.selectedStatus.value == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => controller.onStatusChanged(value),
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
      ),
    );
  }

  Widget _buildOpnameCard(
    BuildContext context,
    ThemeData theme,
    OpnameSummaryEntry entry,
    bool isMobile,
  ) {
    final timeStr = DateFormat('HH:mm').format(entry.date);
    final isDraft = entry.isDraft;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDraft ? Colors.orange.withValues(alpha: 0.5) : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Get.toNamed(
            Routes.OPNAME_DETAIL,
            arguments: {'opnameId': entry.opname.id},
          )?.then((_) => controller.loadOpnames(refresh: true));
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          entry.code,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDraft ? Colors.orange.shade50 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDraft ? Colors.orange.shade300 : Colors.green.shade300,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isDraft ? 'DRAFT' : 'FINAL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDraft ? Colors.orange.shade900 : Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                  ),
                  if (isDraft && controller.canManage) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      tooltip: 'Hapus Draft',
                      onPressed: () => controller.deleteDraft(entry),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.totalItems} Produk',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  if (entry.totalDifferenceItems > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        '${entry.totalDifferenceItems} Ada Selisih',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Text(
                        'Semua Cocok',
                        style: TextStyle(fontSize: 11, color: Colors.teal.shade900),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (entry.creatorName != null)
                    Text(
                      'Oleh: ${entry.creatorName}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                    ),
                ],
              ),
              if (entry.opname.note != null && entry.opname.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Catatan: ${entry.opname.note}',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: theme.colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
