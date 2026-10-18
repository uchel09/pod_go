import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../controllers/units_controller.dart';

class UnitsView extends GetView<UnitsController> {
  const UnitsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Satuan Produk'),
        centerTitle: false,
        actions: [
          Obx(() {
            if (!controller.canEdit) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Tambah Satuan',
              icon: const Icon(Icons.add),
              onPressed: () => controller.showAddUnitDialog(context),
            );
          }),
        ],
      ),
      floatingActionButton: Obx(() {
        if (!controller.canEdit) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: () => controller.showAddUnitDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Tambah Satuan'),
        );
      }),
      body: Obx(() {
        // Cek hak akses melihat satuan
        if (!controller.canView) {
          return const ErrorState(
            title: 'Akses Terbatas',
            message: 'Anda tidak memiliki hak akses untuk melihat data satuan produk.',
            icon: Icons.lock_outline,
          );
        }

        if (controller.isLoading.value && controller.allUnits.isEmpty) {
          return const LoadingIndicator(message: 'Memuat data satuan...');
        }

        final items = controller.filteredUnits;

        return Column(
          children: [
            // Search Bar & Info Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: controller.searchController,
                onChanged: controller.updateSearch,
                decoration: InputDecoration(
                  hintText: 'Cari satuan atau simbol...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.searchQuery.value.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: controller.clearSearch,
                        )
                      : null,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Info count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Total: ${controller.allUnits.length} satuan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (controller.searchQuery.value.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(Ditemukan: ${items.length})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 12),

            // Content List / Empty State
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.straighten_outlined,
                      title: controller.searchQuery.value.isEmpty
                          ? 'Belum Ada Satuan'
                          : 'Tidak Ditemukan',
                      message: controller.searchQuery.value.isEmpty
                          ? 'Daftar satuan ukuran produk masih kosong. Tambahkan satuan baru untuk produk Anda.'
                          : 'Tidak ada satuan yang cocok dengan pencarian "${controller.searchQuery.value}".',
                      action: controller.canEdit && controller.searchQuery.value.isEmpty
                          ? FilledButton.icon(
                              onPressed: () => controller.showAddUnitDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah Satuan Pertama'),
                            )
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: items.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final unit = items[index];
                        return _buildUnitCard(context, unit);
                      },
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildUnitCard(BuildContext context, Unit unit) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text(
            unit.symbol.length <= 3 ? unit.symbol : unit.symbol.substring(0, 3),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        title: Text(
          unit.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Simbol: ${unit.symbol}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Obx(() {
          if (!controller.canEdit) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit Satuan',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => controller.showEditUnitDialog(context, unit),
              ),
              IconButton(
                tooltip: 'Hapus Satuan',
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                onPressed: () => controller.confirmDeleteUnit(context, unit),
              ),
            ],
          );
        }),
      ),
    );
  }
}
