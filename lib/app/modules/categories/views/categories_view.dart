import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../controllers/categories_controller.dart';

class CategoriesView extends GetView<CategoriesController> {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori Produk'),
        centerTitle: false,
        actions: [
          Obx(() {
            if (!controller.canEdit) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Tambah Kategori',
              icon: const Icon(Icons.add),
              onPressed: () => controller.showAddCategoryDialog(context),
            );
          }),
        ],
      ),
      floatingActionButton: Obx(() {
        if (!controller.canEdit) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: () => controller.showAddCategoryDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Tambah Kategori'),
        );
      }),
      body: Obx(() {
        // Cek hak akses melihat kategori
        if (!controller.canView) {
          return const ErrorState(
            title: 'Akses Terbatas',
            message:
                'Anda tidak memiliki hak akses untuk melihat data kategori produk.',
            icon: Icons.lock_outline,
          );
        }

        if (controller.isLoading.value && controller.allCategories.isEmpty) {
          return const LoadingIndicator(message: 'Memuat data kategori...');
        }

        final items = controller.filteredCategories;

        return Column(
          children: [
            // Search Bar & Info Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: controller.searchController,
                onChanged: controller.updateSearch,
                decoration: InputDecoration(
                  hintText: 'Cari kategori...',
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),

            // Info count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Total: ${controller.allCategories.length} kategori',
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
                      icon: Icons.category_outlined,
                      title: controller.searchQuery.value.isEmpty
                          ? 'Belum Ada Kategori'
                          : 'Tidak Ditemukan',
                      message: controller.searchQuery.value.isEmpty
                          ? 'Daftar kategori produk masih kosong. Tambahkan kategori baru untuk mengelompokkan produk Anda.'
                          : 'Tidak ada kategori yang cocok dengan pencarian "${controller.searchQuery.value}".',
                      action:
                          controller.canEdit &&
                              controller.searchQuery.value.isEmpty
                          ? FilledButton.icon(
                              onPressed: () =>
                                  controller.showAddCategoryDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah Kategori Pertama'),
                            )
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: items.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final cat = items[index];
                        return _buildCategoryCard(context, cat);
                      },
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category category) {
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
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.folder_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Obx(() {
          if (!controller.canEdit) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit Kategori',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    controller.showEditCategoryDialog(context, category),
              ),
              IconButton(
                tooltip: 'Hapus Kategori',
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: () =>
                    controller.confirmDeleteCategory(context, category),
              ),
            ],
          );
        }),
      ),
    );
  }
}
