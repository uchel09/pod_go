import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/audit/audit_actions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/repositories/audit_repository.dart';
import '../controllers/activity_log_controller.dart';

class ActivityLogView extends GetView<ActivityLogController> {
  const ActivityLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Aktivitas'),
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
        if (!controller.canViewAudit) {
          return const ErrorState(
            title: 'Akses Ditolak',
            message: 'Anda tidak memiliki hak akses untuk melihat riwayat aktivitas (audit.view).',
            icon: Icons.lock_outline,
          );
        }

        return Column(
          children: [
            _buildFilterHeader(context, theme),
            const Divider(height: 1),
            Expanded(
              child: _buildLogContent(context, theme),
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
                    hintText: 'Cari aksi, produk, atau nama...',
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
              if (controller.selectedDateFilter.value != 'all' ||
                  controller.selectedCategory.value != 'Semua' ||
                  controller.selectedUserId.value != null ||
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

          // Baris 2: Filter Horizontal (Tanggal, Kategori, User)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Tanggal
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

                const SizedBox(width: 8),
                Container(height: 20, width: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(width: 8),

                // Kategori Aksi
                for (final cat in AuditActions.categories)
                  _buildChip(
                    label: cat,
                    isSelected: controller.selectedCategory.value == cat,
                    onSelected: () => controller.setCategoryFilter(cat),
                    theme: theme,
                  ),

                // User / Kasir Dropdown
                if (controller.users.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(height: 20, width: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(width: 8),
                  _buildChip(
                    label: 'Semua Pengguna',
                    isSelected: controller.selectedUserId.value == null,
                    onSelected: () => controller.setUserFilter(null),
                    theme: theme,
                  ),
                  for (final u in controller.users)
                    _buildChip(
                      label: u.displayName,
                      icon: Icons.person_outline,
                      isSelected: controller.selectedUserId.value == u.id,
                      onSelected: () => controller.setUserFilter(u.id),
                      theme: theme,
                    ),
                ],
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: icon != null ? Icon(icon, size: 14, color: isSelected ? Colors.white : theme.colorScheme.primary) : null,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        selectedColor: theme.colorScheme.primary,
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

  Widget _buildLogContent(BuildContext context, ThemeData theme) {
    if (controller.isLoading.value) {
      return const Center(child: LoadingIndicator(message: 'Memuat riwayat aktivitas...'));
    }

    if (controller.logs.isEmpty) {
      return const EmptyState(
        title: 'Belum Ada Aktivitas',
        message: 'Tidak ditemukan riwayat log aktivitas untuk filter yang dipilih.',
        icon: Icons.history_edu_outlined,
      );
    }

    final grouped = controller.groupedLogs;
    final dayKeys = grouped.keys.toList();

    return ListView.builder(
      controller: controller.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: dayKeys.length + (controller.isLoadingMore.value ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == dayKeys.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final dayKey = dayKeys[index];
        final entriesForDay = grouped[dayKey]!;

        DateTime? dayDate;
        try {
          dayDate = DateFormat('yyyy-MM-dd').parse(dayKey);
        } catch (_) {}

        final formattedDay = dayDate != null
            ? DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dayDate)
            : dayKey;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    formattedDay,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entriesForDay.length} aksi',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entriesForDay.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, itemIdx) {
                  final log = entriesForDay[itemIdx];
                  return _buildLogTile(context, theme, log);
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _buildLogTile(BuildContext context, ThemeData theme, AuditEntry log) {
    final category = AuditActions.getCategory(log.action);
    final sentence = AuditActions.formatHumanSentence(
      action: log.action,
      userName: log.userName,
      detail: log.detail,
    );

    IconData icon;
    Color iconColor;

    switch (category) {
      case 'Produk':
        icon = Icons.inventory_2_outlined;
        iconColor = Colors.teal;
        break;
      case 'Stok':
        icon = Icons.swap_vert_rounded;
        iconColor = Colors.orange.shade800;
        break;
      case 'Penjualan':
        icon = Icons.point_of_sale_outlined;
        iconColor = Colors.green.shade800;
        break;
      case 'Akun':
        icon = Icons.lock_person_outlined;
        iconColor = Colors.indigo;
        break;
      case 'Pengaturan':
        icon = Icons.settings_outlined;
        iconColor = Colors.blueGrey;
        break;
      default:
        icon = Icons.bolt_outlined;
        iconColor = theme.colorScheme.primary;
        break;
    }

    final timeStr = DateFormat('HH:mm:ss').format(log.createdAt.toLocal());

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: iconColor.withValues(alpha: 0.12),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        sentence,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
      ),
      subtitle: Row(
        children: [
          Text(
            timeStr,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              category,
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showLogDetailDialog(context, theme, log, category),
    );
  }

  void _showLogDetailDialog(BuildContext context, ThemeData theme, AuditEntry log, String category) {
    final formattedDateTime = DateFormat('EEEE, dd MMMM yyyy HH:mm:ss', 'id_ID').format(log.createdAt.toLocal());
    final detailMap = log.parsedDetail;
    final hasDiff = detailMap.containsKey('diff') && detailMap['diff'] is Map;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.history_edu, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Detail Log Aktivitas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(log.action, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
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
                const Divider(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildInfoRow('Waktu', formattedDateTime),
                        _buildInfoRow('Pelaku (User)', log.userName),
                        _buildInfoRow('Entitas', '${log.entity} (ID: ${log.entityId ?? "-"})'),
                        if (log.deviceId != null) _buildInfoRow('Device ID', log.deviceId!),
                        const SizedBox(height: 12),

                        if (hasDiff) ...[
                          const Text(
                            'Perubahan Data (Diff Sebelum / Sesudah):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          _buildDiffTable(theme, detailMap['diff'] as Map),
                          const SizedBox(height: 14),
                        ],

                        const Text(
                          'Data JSON Detail:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert(detailMap),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Salin JSON'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: log.detail ?? jsonEncode(detailMap)));
                        Get.snackbar('Tersalin', 'Data JSON berhasil disalin ke clipboard');
                      },
                    ),
                    const SizedBox(width: 8),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffTable(ThemeData theme, Map diff) {
    return Table(
      border: TableBorder.all(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(6)),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(3),
        2: FlexColumnWidth(3),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: const [
            Padding(padding: EdgeInsets.all(6), child: Text('Kolom', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            Padding(padding: EdgeInsets.all(6), child: Text('Sebelum', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            Padding(padding: EdgeInsets.all(6), child: Text('Sesudah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
          ],
        ),
        for (final entry in diff.entries)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(6), child: Text('${entry.key}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  entry.value is Map ? '${entry.value["old"] ?? "-"}' : '-',
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  entry.value is Map ? '${entry.value["new"] ?? "-"}' : '${entry.value}',
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
