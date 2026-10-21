import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_state.dart';
import '../../../routes/app_pages.dart';
import '../controllers/expenses_controller.dart';

class ExpensesView extends GetView<ExpensesController> {
  const ExpensesView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengeluaran Operasional'),
        actions: [
          IconButton(
            tooltip: 'Kelola Kategori',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => _showManageCategoriesDialog(context),
          ),
          IconButton(
            tooltip: 'Segarkan Data',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.fetchExpenses(),
          ),
        ],
      ),
      body: Obx(() {
        // Gating Lisensi
        if (!controller.hasExpensesFeature) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                margin: const EdgeInsets.all(24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.amber.shade100,
                        child: Icon(Icons.lock, size: 40, color: Colors.amber.shade900),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Fitur Pengeluaran Operasional Terkunci',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pencatatan biaya sewa, listrik, air, dan operasional lainnya serta analisis laba bersih hanya tersedia pada lisensi Semi-Premium ke atas.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Upgrade ke Semi-Premium'),
                        onPressed: () => FeatureGate.to.requireFeature(Feature.expenses),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Pengecekan Izin
        if (!controller.canView) {
          return const ErrorState(
            title: 'Akses Ditolak',
            message: 'Anda tidak memiliki hak akses melihat data pengeluaran (expense.view).',
            icon: Icons.lock_outline,
          );
        }

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 720;
            return Column(
              children: [
                _buildSummaryAndFilters(context, isDesktop),
                const Divider(height: 1),
                Expanded(
                  child: controller.expenses.isEmpty
                      ? _buildEmptyState(context)
                      : _buildExpensesList(context, isDesktop),
                ),
              ],
            );
          },
        );
      }),
      floatingActionButton: Obx(() {
        if (!controller.hasExpensesFeature || !controller.canManage) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Catat Pengeluaran'),
          onPressed: () async {
            final result = await Get.toNamed(Routes.EXPENSE_FORM);
            if (result == true) {
              controller.fetchExpenses();
            }
          },
        );
      }),
    );
  }

  Widget _buildSummaryAndFilters(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24.0 : 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris Total Pengeluaran Periode
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL BIAYA OPERASIONAL (PERIODE)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Obx(() => Text(
                          formatRupiah(controller.totalExpensesPeriod.value),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        )),
                  ],
                ),
              ),
              if (controller.canManage)
                OutlinedButton.icon(
                  icon: const Icon(Icons.category, size: 18),
                  label: const Text('Kategori'),
                  onPressed: () => _showManageCategoriesDialog(context),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Chip Filter Waktu
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateChip('Bulan Ini', 'thisMonth'),
                const SizedBox(width: 8),
                _buildDateChip('Hari Ini', 'today'),
                const SizedBox(width: 8),
                _buildDateChip('Kemarin', 'yesterday'),
                const SizedBox(width: 8),
                _buildDateChip('7 Hari', '7days'),
                const SizedBox(width: 8),
                _buildDateChip('Semua', 'all'),
                const SizedBox(width: 8),
                Obx(() {
                  final isCustom = controller.selectedDateFilter.value == 'custom';
                  final range = controller.customDateRange.value;
                  final label = (isCustom && range != null)
                      ? '${dateFmt.format(range.start)} - ${dateFmt.format(range.end)}'
                      : 'Kustom Tanggal';
                  return FilterChip(
                    label: Text(label),
                    selected: isCustom,
                    onSelected: (_) => controller.pickCustomDateRange(context),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Filter Kategori & Status
          Row(
            children: [
              // Dropdown Kategori
              Expanded(
                flex: 2,
                child: Obx(() => DropdownButtonFormField<int?>(
                      initialValue: controller.selectedCategoryId.value,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Semua Kategori'),
                        ),
                        ...controller.categories.map((c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name),
                            )),
                      ],
                      onChanged: controller.setCategoryFilter,
                    )),
              ),
              const SizedBox(width: 8),

              // Dropdown Status
              Expanded(
                flex: 1,
                child: Obx(() => DropdownButtonFormField<String>(
                      initialValue: controller.selectedStatus.value,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Semua')),
                        DropdownMenuItem(value: 'active', child: Text('Aktif')),
                        DropdownMenuItem(value: 'void', child: Text('Void')),
                      ],
                      onChanged: (val) {
                        if (val != null) controller.setStatusFilter(val);
                      },
                    )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, String value) {
    return Obx(() => FilterChip(
          label: Text(label),
          selected: controller.selectedDateFilter.value == value,
          onSelected: (_) => controller.setDateFilter(value),
        ));
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Belum Ada Catatan Pengeluaran',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tidak ditemukan pengeluaran pada rentang waktu atau filter yang dipilih.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesList(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');

    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24.0 : 12.0,
        vertical: 12.0,
      ),
      itemCount: controller.expenses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = controller.expenses[index];
        final isVoid = item.isVoided;

        return Card(
          elevation: 0,
          color: isVoid ? Colors.grey.shade50 : theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isVoid ? Colors.grey.shade300 : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Kategori / Void
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isVoid ? Colors.grey.shade200 : Colors.red.shade50,
                  child: Icon(
                    isVoid ? Icons.block : Icons.money_off,
                    color: isVoid ? Colors.grey.shade600 : Colors.red.shade800,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Info Pengeluaran
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.categoryName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                decoration: isVoid ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          Text(
                            formatRupiah(item.amount),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isVoid ? Colors.grey.shade500 : Colors.red.shade800,
                              decoration: isVoid ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            dateFmt.format(item.date.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 8),
                          _buildBadge(
                            label: _formatPaymentMethod(item.paymentMethod),
                            bg: theme.colorScheme.surfaceContainerHighest,
                            fg: theme.colorScheme.onSurfaceVariant,
                          ),
                          if (isVoid) ...[
                            const SizedBox(width: 6),
                            _buildBadge(
                              label: 'BATAL (VOID)',
                              bg: Colors.red.shade100,
                              fg: Colors.red.shade900,
                            ),
                          ],
                        ],
                      ),
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Catatan: ${item.note}',
                          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                      if (isVoid && item.voidReason != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Alasan Void: ${item.voidReason} (oleh ${item.voidedByName ?? 'Kasir'})',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade800, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),

                // Tombol Aksi (Edit & Void)
                if (controller.canManage && !isVoid) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Aksi',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        final res = await Get.toNamed(
                          Routes.EXPENSE_FORM,
                          arguments: item.expense,
                        );
                        if (res == true) controller.fetchExpenses();
                      } else if (val == 'void') {
                        controller.handleVoidExpense(context, item);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Ubah Pengeluaran'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'void',
                        child: Row(
                          children: [
                            Icon(Icons.block, size: 18, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text('Batalkan (Void)', style: TextStyle(color: Colors.red.shade700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge({required String label, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatPaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Tunai';
      case 'transfer':
        return 'Transfer';
      default:
        return 'Lainnya';
    }
  }

  // Dialog Kelola Kategori Pengeluaran
  void _showManageCategoriesDialog(BuildContext context) {
    final newCategoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.category_outlined),
            SizedBox(width: 8),
            Text('Kelola Kategori Biaya'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tambah Cepat
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: newCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'Tambah Kategori Baru',
                        hintText: 'Contoh: Kemasan Box',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = newCategoryController.text.trim();
                      if (name.isNotEmpty) {
                        controller.addCategory(name);
                        newCategoryController.clear();
                      }
                    },
                    child: const Text('Tambah'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Daftar Kategori
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Obx(() {
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: controller.categories.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (cCtx, i) {
                      final cat = controller.categories[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          cat.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cat.isActive ? null : Colors.grey,
                            decoration: cat.isActive ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: cat.isActive,
                              onChanged: (active) {
                                controller.updateCategory(cat.id, cat.name, active);
                              },
                            ),
                            IconButton(
                              tooltip: 'Hapus Kategori',
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              onPressed: () async {
                                final confirm = await ConfirmDialog.show(
                                  context: context,
                                  title: 'Hapus Kategori',
                                  message: 'Hapus kategori "${cat.name}"?\nKategori yang sudah dipakai tidak dapat dihapus.',
                                  confirmText: 'Hapus',
                                  isDestructive: true,
                                );
                                if (confirm) {
                                  controller.deleteCategory(cat.id, cat.name);
                                }
                              },
                            ),
                          ],
                        ),
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }
}
