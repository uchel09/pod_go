import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../../../routes/app_pages.dart';
import '../controllers/products_controller.dart';

class ProductsView extends GetView<ProductsController> {
  const ProductsView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 600;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Katalog Produk'),
            centerTitle: false,
            actions: [
              IconButton(
                tooltip: 'Cetak Label Barcode',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => Get.toNamed(Routes.PRODUCT_LABELS),
              ),
              Obx(() {
                if (!controller.canEdit) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilledButton.tonalIcon(
                    onPressed: () => controller.onAddProductPressed(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(controller.addButtonLabel),
                  ),
                );
              }),
            ],
          ),
          floatingActionButton: Obx(() {
            if (!controller.canEdit || isDesktop) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => controller.onAddProductPressed(context),
              icon: const Icon(Icons.add),
              label: Text(controller.addButtonLabel),
            );
          }),
          body: Obx(() {
            if (!controller.canView) {
              return const ErrorState(
                title: 'Akses Ditolak',
                message: 'Anda tidak memiliki izin untuk melihat katalog produk.',
                icon: Icons.lock_outline,
              );
            }

            if (controller.isLoading.value && controller.allProducts.isEmpty) {
              return const LoadingIndicator(message: 'Memuat data produk...');
            }

            final items = controller.filteredProducts;

            return Column(
              children: [
                _buildSearchAndFilters(context),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState(context)
                      : isDesktop
                          ? _buildDesktopGrid(context, items)
                          : _buildMobileList(context, items),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _buildSearchAndFilters(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Baris 1: Pencarian
          TextField(
            controller: controller.searchController,
            onChanged: controller.updateSearch,
            decoration: InputDecoration(
              hintText: 'Cari nama, SKU, atau barcode...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Obx(
                () => controller.searchQuery.value.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: controller.clearSearch,
                      )
                    : const SizedBox.shrink(),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),

          // Baris 2: Filter Kategori & Status Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Obx(
              () => Row(
                children: [
                  // Filter Status
                  FilterChip(
                    label: const Text('Semua'),
                    selected: controller.selectedStatusFilter.value == 'all',
                    onSelected: (_) => controller.filterByStatus('all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Aktif'),
                    selected: controller.selectedStatusFilter.value == 'active',
                    onSelected: (_) => controller.filterByStatus('active'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Nonaktif'),
                    selected: controller.selectedStatusFilter.value == 'inactive',
                    onSelected: (_) => controller.filterByStatus('inactive'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                    label: const Text('Stok Menipis'),
                    selected: controller.selectedStatusFilter.value == 'low_stock',
                    onSelected: (_) => controller.filterByStatus('low_stock'),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 1,
                    height: 24,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: 8),

                  // Filter Kategori Dropdown / Chip
                  FilterChip(
                    label: Text(
                      controller.selectedCategoryId.value == null
                          ? 'Semua Kategori'
                          : controller.getCategoryName(controller.selectedCategoryId.value),
                    ),
                    selected: controller.selectedCategoryId.value != null,
                    onSelected: (_) {
                      _showCategoryFilterSheet(context);
                    },
                    avatar: const Icon(Icons.category_outlined, size: 16),
                  ),
                  if (controller.selectedCategoryId.value != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Hapus filter kategori',
                      onPressed: () => controller.filterByCategory(null),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryFilterSheet(BuildContext context) {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pilih Kategori',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('Semua Kategori'),
                      trailing: controller.selectedCategoryId.value == null ? const Icon(Icons.check) : null,
                      onTap: () {
                        controller.filterByCategory(null);
                        Get.back();
                      },
                    ),
                    ...controller.categories.map((cat) {
                      return ListTile(
                        title: Text(cat.name),
                        trailing: controller.selectedCategoryId.value == cat.id ? const Icon(Icons.check) : null,
                        onTap: () {
                          controller.filterByCategory(cat.id);
                          Get.back();
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (controller.searchQuery.value.isNotEmpty ||
        controller.selectedCategoryId.value != null ||
        controller.selectedStatusFilter.value != 'all') {
      return EmptyState(
        title: 'Produk Tidak Ditemukan',
        message: 'Tidak ada produk yang cocok dengan kriteria pencarian atau filter saat ini.',
        icon: Icons.search_off_outlined,
        action: TextButton(
          onPressed: () {
            controller.clearSearch();
            controller.filterByCategory(null);
            controller.filterByStatus('all');
          },
          child: const Text('Reset Filter'),
        ),
      );
    }

    return EmptyState(
      title: 'Belum Ada Produk',
      message: 'Tambahkan produk barang dagangan toko Anda untuk memulai transaksi.',
      icon: Icons.inventory_2_outlined,
      action: controller.canEdit
          ? FilledButton.icon(
              onPressed: () => controller.onAddProductPressed(context),
              icon: const Icon(Icons.add),
              label: Text(controller.addButtonLabel),
            )
          : null,
    );
  }

  // Mobile List View (< 600px)
  Widget _buildMobileList(BuildContext context, List<Product> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = items[index];
        return _buildProductCard(context, product, isGrid: false);
      },
    );
  }

  // Desktop Grid View (>= 600px)
  Widget _buildDesktopGrid(BuildContext context, List<Product> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 240,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final product = items[index];
        return _buildProductCard(context, product, isGrid: true);
      },
    );
  }

  Widget _buildProductCard(BuildContext context, Product product, {required bool isGrid}) {
    final theme = Theme.of(context);
    final isLocked = controller.isProductLocked(product);
    final isLowStock = product.currentStock <= product.minStock;
    final unitSymbol = controller.getUnitSymbol(product.unitId);
    final catName = controller.getCategoryName(product.categoryId);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLocked
              ? Colors.red.shade300
              : (isLowStock ? Colors.orange.shade300 : theme.colorScheme.outlineVariant),
          width: isLocked || isLowStock ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Baris: Nama & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kategori: $catName',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badges
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!product.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Nonaktif', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      )
                    else if (isLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Terkunci',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (isLowStock)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Stok Menipis',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            if (isLocked) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Terkunci - upgrade atau nonaktifkan produk lain',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            if (isGrid) const Spacer() else const SizedBox(height: 12),

            // Informasi Barcode & SKU
            Row(
              children: [
                Icon(Icons.qr_code, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    product.barcode ?? product.internalCode ?? (product.sku != null ? 'SKU: ${product.sku}' : '-'),
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Stok Badge (Bisa diklik untuk kelola stok)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => controller.showStockAdjustmentDialog(
                    context: context,
                    product: product,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLowStock ? Colors.orange.shade50 : theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isLowStock ? Colors.orange.shade300 : theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 13,
                          color: isLowStock ? Colors.orange.shade800 : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Stok: ${product.currentStock} $unitSymbol',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                            color: isLowStock ? Colors.orange.shade800 : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),

            // Baris Harga & Aksi
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatRupiah(product.sellPrice),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (controller.canViewCost && product.costPrice > 0)
                        Text(
                          'Beli: ${formatRupiah(product.costPrice)}',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (controller.canEdit)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (product.codeType != 'manufacturer')
                        IconButton(
                          tooltip: 'Cetak Label Barcode',
                          icon: const Icon(Icons.print_outlined, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => Get.toNamed(
                            Routes.PRODUCT_LABELS,
                            arguments: {'productId': product.id},
                          ),
                        ),
                      IconButton(
                        tooltip: 'Kelola Stok (+/-)',
                        icon: Icon(
                          Icons.swap_vert_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () => controller.showStockAdjustmentDialog(
                          context: context,
                          product: product,
                        ),
                      ),
                      IconButton(
                        tooltip: product.isActive ? 'Nonaktifkan Produk' : 'Aktifkan Produk',
                        icon: Icon(
                          product.isActive ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 18,
                          color: product.isActive ? null : Colors.grey,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () => controller.toggleProductActive(product),
                      ),
                      IconButton(
                        tooltip: isLocked ? 'Terkunci oleh kuota' : 'Edit Produk',
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: isLocked ? Colors.grey : null,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: isLocked
                            ? null
                            : () => controller.showProductFormDialog(
                                  context: context,
                                  productToEdit: product,
                                ),
                      ),
                      IconButton(
                        tooltip: 'Hapus Produk',
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () => controller.confirmDeleteProduct(context, product),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
