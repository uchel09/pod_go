import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../routes/app_pages.dart';

import '../../../core/printing/printer_manager.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/sale_repository.dart';
import '../controllers/pos_controller.dart';

class PosView extends GetView<PosController> {
  const PosView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!controller.canSell) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kasir (POS)')),
        body: const ErrorState(
          title: 'Akses Ditolak',
          message: 'Anda tidak memiliki hak akses kasir (pos.sell).',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Obx(() {
      final isCartEmpty = controller.cartItems.isEmpty;

      return PopScope(
        canPop: isCartEmpty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldLeave = await ConfirmDialog.show(
            context: context,
            title: 'Keranjang Masih Berisi',
            message:
                'Masih ada barang di keranjang belanja. Apakah Anda yakin ingin keluar dari kasir?',
            confirmText: 'Keluar',
            cancelText: 'Tetap di Kasir',
            isDestructive: true,
          );
          if (shouldLeave && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f2): () {
              if (controller.cartItems.isNotEmpty && !controller.isSaving.value) {
                _showPaymentDialog(context);
              }
            },
            const SingleActivator(LogicalKeyboardKey.f3): () {
              controller.refocusSearch();
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controller.searchController.text.isNotEmpty) {
                controller.clearSearch();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Kasir (POS)'),
                actions: [
                  // Scanner Kamera (Android Only)
                  if (controller.isCameraSupported)
                    IconButton(
                      tooltip: 'Scan Kamera',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () => _handleCameraScan(context),
                    ),

                  // Buka Laci Kasir Manual
                  Obx(() {
                    if (!PrinterManager.to.cashDrawer.value ||
                        !PrinterManager.to.isHardwareConfigured) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: 'Buka Laci Kasir',
                      icon: const Icon(Icons.point_of_sale_outlined),
                      onPressed: controller.openCashDrawer,
                    );
                  }),

                  // Keranjang Tertahan (Hold Carts)
                  Obx(() {
                    final count = controller.heldCarts.length;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Pesanan Tertahan ($count)',
                          icon: const Icon(Icons.pause_circle_outline),
                          onPressed: () => _showHeldCartsDialog(context),
                        ),
                        if (count > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    );
                  }),

                  // Riwayat Penjualan
                  if (controller.canViewHistory)
                    IconButton(
                      tooltip: 'Riwayat Penjualan',
                      icon: const Icon(Icons.history),
                      onPressed: () => Get.toNamed(Routes.SALES_HISTORY),
                    ),

                  // Pengaturan POS Cepat
                  IconButton(
                    tooltip: 'Pengaturan Kasir',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _showPosSettingsDialog(context),
                  ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 768;

                  if (isDesktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Panel Kiri: Katalog Produk & Pencarian
                        Expanded(
                          flex: 6,
                          child: _buildProductCatalogPane(context, theme),
                        ),
                        const VerticalDivider(width: 1),
                        // Panel Kanan: Keranjang & Pembayaran
                        SizedBox(
                          width: 360,
                          child: _buildCartPane(context, theme, isDesktop: true),
                        ),
                      ],
                    );
                  }

                  // Tampilan Mobile: Produk di atas, Cart bar di bawah
                  return Stack(
                    children: [
                      Positioned.fill(
                        bottom: 72,
                        child: _buildProductCatalogPane(context, theme),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildMobileBottomBar(context, theme),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }

  // ==========================================
  // PANEL KATALOG PRODUK
  // ==========================================

  Widget _buildProductCatalogPane(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // 1. Search Bar & Filter Favorit
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: controller.searchFocusNode,
                  controller: controller.searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nama, SKU, atau scan barcode...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: Obx(() => controller.searchQuery.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: controller.clearSearch,
                          )
                        : const SizedBox.shrink()),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: controller.updateSearch,
                ),
              ),
              const SizedBox(width: 8),
              Obx(() {
                final isFavOnly = controller.onlyFavoritesFilter.value;
                return FilterChip(
                  avatar: Icon(
                    isFavOnly ? Icons.star : Icons.star_border,
                    size: 18,
                    color: isFavOnly ? Colors.amber.shade800 : null,
                  ),
                  label: const Text('Favorit'),
                  selected: isFavOnly,
                  onSelected: (val) => controller.onlyFavoritesFilter.value = val,
                );
              }),
            ],
          ),
        ),

        // 2. Kategori Filter Horizontal Chips
        Obx(() {
          final cats = controller.categories;
          final selectedCat = controller.selectedCategoryId.value;

          return SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Semua'),
                    selected: selectedCat == null,
                    onSelected: (_) => controller.filterByCategory(null),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                ...cats.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: selectedCat == cat.id,
                      onSelected: (_) => controller.filterByCategory(cat.id),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const Divider(height: 12),

        // 3. Grid / List Produk
        Expanded(
          child: Obx(() {
            if (controller.isLoading.value) {
              return const Center(child: LoadingIndicator(message: 'Memuat produk...'));
            }

            final items = controller.filteredProducts;
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'Tidak ada produk yang cocok',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () {
                          controller.clearSearch();
                          controller.filterByCategory(null);
                          controller.onlyFavoritesFilter.value = false;
                        },
                        child: const Text('Reset Filter'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisExtent: 140,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final product = items[index];
                return _buildProductGridCard(context, product, theme);
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildProductGridCard(BuildContext context, Product product, ThemeData theme) {
    final isLocked = controller.isProductLocked(product);
    final isLowStock = product.currentStock <= product.minStock;
    final isOut = product.currentStock <= 0;

    return Obx(() {
      final isFav = controller.favoriteProductIds.contains(product.id);

      return Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isLocked
                ? Colors.red.shade300
                : (isOut ? Colors.grey.shade400 : theme.colorScheme.outlineVariant),
            width: isLocked ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isLocked ? null : () => controller.addToCart(product),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Baris Atas: Nama & Bintang Favorit
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isOut ? Colors.grey : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => controller.toggleFavorite(product.id),
                      child: Icon(
                        isFav ? Icons.star : Icons.star_border,
                        size: 18,
                        color: isFav ? Colors.amber.shade700 : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Baris Bawah: Harga & Stok
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatRupiah(product.sellPrice),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Stok: ${product.currentStock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOut
                            ? Colors.red
                            : (isLowStock ? Colors.orange.shade800 : Colors.grey.shade700),
                        fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ==========================================
  // PANEL KERANJANG (DESKTOP & BOTTOM SHEET)
  // ==========================================

  Widget _buildCartPane(BuildContext context, ThemeData theme, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isDesktop)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        // Header Keranjang
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(() => Text(
                    'Keranjang (${controller.totalItemsQty} Item)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  )),
              Obx(() => Row(
                children: [
                  IconButton(
                    tooltip: 'Tahan Pesanan (Hold)',
                    icon: const Icon(Icons.pause, size: 20),
                    onPressed: controller.cartItems.isNotEmpty
                        ? () => _showHoldCartDialog(context)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Kosongkan Keranjang',
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    onPressed: controller.cartItems.isNotEmpty ? controller.clearCart : null,
                  ),
                  if (!isDesktop)
                    IconButton(
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Get.back(),
                    ),
                ],
              )),
            ],
          ),
        ),
        const Divider(height: 1),

        // List Item Keranjang
        Expanded(
          child: Obx(() {
            final items = controller.cartItems;
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Keranjang Masih Kosong',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ketuk produk di katalog atau scan barcode untuk menambahkan barang.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildCartItemTile(context, item, theme);
              },
            );
          }),
        ),
        const Divider(height: 1),

        // Ringkasan & Tombol Bayar
        _buildCartSummarySection(context, theme),
      ],
    );
  }

  Widget _buildCartItemTile(BuildContext context, PosCartItem item, ThemeData theme) {
    return Obx(() {
      final subtotal = item.subtotal;
      final discount = item.discount.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Baris 1: Nama & Subtotal
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatRupiah(subtotal),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Baris 2: Harga Satuan, Diskon Item, Stepper Qty
            Row(
              children: [
                Text(
                  formatRupiah(item.product.sellPrice),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (controller.canDiscount) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showItemDiscountDialog(context, item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: discount > 0 ? Colors.green.shade100 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        discount > 0 ? 'Disc: -${formatRupiah(discount)}' : '+ Diskon',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: discount > 0 ? Colors.green.shade900 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),

                // Stepper Qty
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => controller.updateQty(item, item.qty.value - 1),
                ),
                InkWell(
                  onTap: () => _showDirectQtyDialog(context, item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${item.qty.value}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => controller.updateQty(item, item.qty.value + 1),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCartSummarySection(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Subtotal
          Obx(() => _buildSummaryRow('Subtotal', formatRupiah(controller.subtotalAmount), theme)),

          // Diskon Total
          Obx(() {
            final disc = controller.totalDiscountAmount;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Total Diskon', style: TextStyle(fontSize: 12)),
                    if (controller.canDiscount) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _showOverallDiscountDialog(context),
                        child: Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.primary),
                      ),
                    ],
                  ],
                ),
                Text(
                  disc > 0 ? '-${formatRupiah(disc)}' : 'Rp 0',
                  style: TextStyle(
                    fontSize: 12,
                    color: disc > 0 ? Colors.green.shade800 : Colors.grey,
                    fontWeight: disc > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            );
          }),

          // Pajak (PPN)
          Obx(() {
            if (!controller.taxEnabled.value || controller.taxRateBps.value <= 0) {
              return const SizedBox.shrink();
            }
            final result = controller.taxResult;
            final isInclusive = result.mode == 'inclusive';
            final label = isInclusive
                ? 'Termasuk ${controller.taxName.value} (${result.ratePercentString})'
                : '${controller.taxName.value} (${result.ratePercentString})';

            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: isInclusive ? FontStyle.italic : FontStyle.normal,
                      color: isInclusive ? Colors.grey.shade600 : null,
                    ),
                  ),
                  Text(
                    formatRupiah(result.tax),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isInclusive ? FontWeight.normal : FontWeight.bold,
                      color: isInclusive ? Colors.grey.shade600 : null,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),

          // Total Akhir
          Obx(() => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL BAYAR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(
                    formatRupiah(controller.finalTotalAmount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              )),
          const SizedBox(height: 12),

          // Tombol Bayar
          Obx(() {
            final hasItems = controller.cartItems.isNotEmpty;
            return FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: hasItems ? () => _showPaymentDialog(context) : null,
              icon: const Icon(Icons.payment),
              label: Text(
                'BAYAR (${formatRupiah(controller.finalTotalAmount)})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ==========================================
  // MOBILE BOTTOM BAR
  // ==========================================

  Widget _buildMobileBottomBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Badge & Ringkasan Cepat (Dapat diketuk untuk membuka keranjang)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showMobileCartSheet(context),
              child: Obx(() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shopping_cart, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${controller.totalItemsQty} Item',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_up, size: 16, color: theme.colorScheme.primary),
                        ],
                      ),
                      Text(
                        formatRupiah(controller.finalTotalAmount),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  )),
            ),
          ),

          // Tombol Buka Keranjang & Tombol Bayar
          Obx(() {
            final hasItems = controller.cartItems.isNotEmpty;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: hasItems ? () => _showMobileCartSheet(context) : null,
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: Text('Keranjang (${controller.cartItems.length})'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: hasItems ? () => _showPaymentDialog(context) : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Bayar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _showMobileCartSheet(BuildContext context) {
    if (Get.isBottomSheetOpen == true) return;
    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: _buildCartPane(context, Theme.of(context), isDesktop: false),
      ),
      isScrollControlled: true,
    );
  }

  // ==========================================
  // SCAN KAMERA & DIALOG JUMLAH (PROMPT KOREKSI)
  // ==========================================

  Future<void> _handleCameraScan(BuildContext context) async {
    final code = await controller.scanWithCamera();
    if (code == null || code.trim().isEmpty) return;

    final product = controller.findProductByBarcode(code);
    if (product == null) {
      controller.notifyProductNotFound(code);
      return;
    }

    if (controller.isProductLocked(product)) {
      controller.notifyProductLocked(product);
      return;
    }

    if (context.mounted) {
      _showCameraQuantityDialog(context, product);
    }
  }

  void _showCameraQuantityDialog(BuildContext context, Product product) {
    final qty = 1.obs;
    final qtyCtrl = TextEditingController(text: '1');
    final existing = controller.cartItems.firstWhereOrNull((i) => i.product.id == product.id);
    final inCartQty = existing?.qty.value ?? 0;
    final currentStock = product.currentStock;
    final isStockConstrained = !controller.allowNegativeStock.value;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatRupiah(product.sellPrice)} • Stok: $currentStock${inCartQty > 0 ? " (di keranjang: $inCartQty)" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color: currentStock <= 0 ? Colors.red : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stepper & Direct Input
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        if (qty.value > 1) {
                          qty.value--;
                          qtyCtrl.text = '${qty.value}';
                        }
                      },
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val) ?? 1;
                          if (parsed > 0) {
                            qty.value = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      onPressed: () {
                        if (isStockConstrained && (inCartQty + qty.value + 1) > currentStock) {
                          Get.snackbar(
                            'Batas Stok Tercapai',
                            'Stok produk hanya $currentStock unit.',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(seconds: 2),
                          );
                          return;
                        }
                        qty.value++;
                        qtyCtrl.text = '${qty.value}';
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Tombol Aksi
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Get.back(),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          final count = int.tryParse(qtyCtrl.text) ?? qty.value;
                          if (count <= 0) return;
                          if (isStockConstrained && (inCartQty + count) > currentStock) {
                            Get.snackbar(
                              'Batas Stok Tercapai',
                              'Stok produk hanya $currentStock unit.',
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 2),
                            );
                            return;
                          }
                          controller.addCartItemWithQty(product, count);
                          Get.back();
                          if (MediaQuery.of(context).size.width < 768) {
                            _showMobileCartSheet(context);
                          }
                        },
                        child: const Text('Tambah'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final count = int.tryParse(qtyCtrl.text) ?? qty.value;
                    if (count <= 0) return;
                    if (isStockConstrained && (inCartQty + count) > currentStock) {
                      Get.snackbar(
                        'Batas Stok Tercapai',
                        'Stok produk hanya $currentStock unit.',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                      );
                      return;
                    }
                    controller.addCartItemWithQty(product, count);
                    Get.back();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        _handleCameraScan(context);
                      }
                    });
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Tambah & scan lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // DIALOG PEMBAYARAN (SPLIT PAYMENT & NOMINAL CEPAT)
  // ==========================================

  void _showPaymentDialog(BuildContext context) {
    final totalDue = controller.finalTotalAmount;

    // Default 1 baris pembayaran Cash sebesar total tagihan
    final rows = <_PaymentRowState>[
      _PaymentRowState(method: 'cash', amount: totalDue),
    ].obs;
    final isProcessingPayment = false.obs;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pembayaran Transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Get.back()),
                  ],
                ),
                const Divider(),

                // Total Tagihan Besar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Tagihan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        formatRupiah(totalDue),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Baris Pembayaran (Split Payment)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Obx(() => Column(
                              children: List.generate(rows.length, (idx) {
                                final row = rows[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    children: [
                                      // Metode Dropdown
                                      DropdownButton<String>(
                                        value: row.method,
                                        items: const [
                                          DropdownMenuItem(value: 'cash', child: Text('Tunai (Cash)')),
                                          DropdownMenuItem(value: 'qris', child: Text('QRIS')),
                                          DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                          DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) row.method = val;
                                          rows.refresh();
                                        },
                                      ),
                                      const SizedBox(width: 8),

                                      // Input Nominal
                                      Expanded(
                                        child: TextField(
                                          controller: row.controller,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            prefixText: 'Rp ',
                                          ),
                                          onChanged: (val) {
                                            row.amount = int.tryParse(val.replaceAll('.', '')) ?? 0;
                                            rows.refresh();
                                          },
                                        ),
                                      ),

                                      if (rows.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                                          onPressed: () => rows.removeAt(idx),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            )),

                        // Tombol Tambah Split Payment
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              rows.add(_PaymentRowState(method: 'qris', amount: 0));
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('+ Tambah Metode (Split Pay)'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Tombol Cepat Nominal Uang
                        const Text('Nominal Cepat (Tunai):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ActionChip(
                              label: const Text('Uang Pas'),
                              onPressed: () {
                                if (rows.isNotEmpty) {
                                  rows.first.updateAmount(totalDue);
                                  rows.refresh();
                                }
                              },
                            ),
                            ..._generateQuickAmounts(totalDue).map((amount) {
                              return ActionChip(
                                label: Text(formatRupiah(amount)),
                                onPressed: () {
                                  if (rows.isNotEmpty) {
                                    rows.first.updateAmount(amount);
                                    rows.refresh();
                                  }
                                },
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),

                // Status Kurang / Kembalian
                Obx(() {
                  final totalPaid = rows.fold<int>(0, (sum, r) => sum + r.amount);
                  final change = totalPaid - totalDue;
                  final isUnderpaid = totalPaid < totalDue;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isUnderpaid ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isUnderpaid ? 'Kurang Bayar:' : 'Kembalian:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isUnderpaid ? Colors.red.shade900 : Colors.green.shade900,
                          ),
                        ),
                        Text(
                          formatRupiah(isUnderpaid ? (totalDue - totalPaid) : change),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isUnderpaid ? Colors.red.shade900 : Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // Tombol Selesaikan Transaksi
                Obx(() {
                  final totalPaid = rows.fold<int>(0, (sum, r) => sum + r.amount);
                  final isUnderpaid = totalPaid < totalDue;
                  final isSaving = controller.isSaving.value || isProcessingPayment.value;

                  return FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: (isUnderpaid || isSaving)
                        ? null
                        : () async {
                            isProcessingPayment.value = true;
                            final payments = rows.map((r) {
                              return CheckoutPayment(method: r.method, amount: r.amount);
                            }).toList();

                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop(); // Tutup dialog bayar
                            }

                            try {
                              await controller.processCheckout(payments: payments);
                            } on AppException catch (e) {
                              e.showSnackbar();
                            } catch (e) {
                              Get.snackbar('Error', 'Gagal memproses transaksi: $e');
                            } finally {
                              isProcessingPayment.value = false;
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('SELESAIKAN PEMBAYARAN', style: TextStyle(fontWeight: FontWeight.bold)),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<int> _generateQuickAmounts(int totalDue) {
    final list = <int>{};
    if (totalDue < 10000) list.add(10000);
    if (totalDue < 20000) list.add(20000);
    if (totalDue < 50000) list.add(50000);
    if (totalDue < 100000) list.add(100000);

    // Bulatkan ke kelipatan 50.000 atau 100.000 terdekat berikutnya
    final next50k = ((totalDue / 50000).ceil()) * 50000;
    if (next50k > totalDue) list.add(next50k);
    final next100k = ((totalDue / 100000).ceil()) * 100000;
    if (next100k > totalDue) list.add(next100k);

    return list.take(4).toList();
  }

  // ==========================================
  // DIALOG DISKON & KUANTITAS
  // ==========================================

  void _showItemDiscountDialog(BuildContext context, PosCartItem item) {
    final controllerText = TextEditingController(text: item.discount.value > 0 ? item.discount.value.toString() : '');

    Get.dialog(
      AlertDialog(
        title: Text('Diskon: ${item.product.name}'),
        content: TextField(
          controller: controllerText,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nominal Diskon per Unit (Rp)',
            prefixText: 'Rp ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.setItemDiscount(item, 0);
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Hapus Diskon'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controllerText.text) ?? 0;
              controller.setItemDiscount(item, val);
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).then((_) => controller.refocusSearch());
  }

  void _showOverallDiscountDialog(BuildContext context) {
    final controllerText = TextEditingController(
      text: controller.overallDiscountValue.value > 0 ? controller.overallDiscountValue.value.toString() : '',
    );
    final isPercent = controller.isOverallDiscountPercent.value.obs;

    Get.dialog(
      AlertDialog(
        title: const Text('Diskon Transaksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Nominal (Rp)'),
                        selected: !isPercent.value,
                        onSelected: (_) => isPercent.value = false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Persen (%)'),
                        selected: isPercent.value,
                        onSelected: (_) => isPercent.value = true,
                      ),
                    ),
                  ],
                )),
            const SizedBox(height: 12),
            Obx(() => TextField(
                  controller: controllerText,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: isPercent.value ? 'Persentase Diskon (%)' : 'Nominal Diskon (Rp)',
                    prefixText: isPercent.value ? null : 'Rp ',
                    suffixText: isPercent.value ? '%' : null,
                    border: const OutlineInputBorder(),
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.setOverallDiscount(0);
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Hapus Diskon'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controllerText.text) ?? 0;
              controller.setOverallDiscount(val, isPercent: isPercent.value);
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    ).then((_) => controller.refocusSearch());
  }

  void _showDirectQtyDialog(BuildContext context, PosCartItem item) {
    final controllerText = TextEditingController(text: item.qty.value.toString());

    Get.dialog(
      AlertDialog(
        title: Text('Ubah Jumlah: ${item.product.name}'),
        content: TextField(
          controller: controllerText,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Jumlah Kuantitas',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(controllerText.text) ?? 1;
              controller.updateQty(item, qty);
              Get.back();
              controller.refocusSearch();
            },
            child: const Text('Ubah'),
          ),
        ],
      ),
    ).then((_) => controller.refocusSearch());
  }

  // ==========================================
  // DIALOG HOLD & SETTINGS
  // ==========================================

  void _showHoldCartDialog(BuildContext context) {
    final nameController = TextEditingController(text: 'Keranjang #${controller.heldCarts.length + 1}');

    Get.dialog(
      AlertDialog(
        title: const Text('Tahan Pesanan (Hold)'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Label Pesanan / Meja',
            hintText: 'Misal: Meja 5 atau Bpk. Rudi',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              controller.holdCurrentCart(customName: nameController.text.trim());
              Get.back();
            },
            child: const Text('Tahan'),
          ),
        ],
      ),
    );
  }

  void _showHeldCartsDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Daftar Pesanan Tertahan'),
        content: SizedBox(
          width: 400,
          child: Obx(() {
            final list = controller.heldCarts;
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Tidak ada pesanan yang ditahan.', textAlign: TextAlign.center),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, index) => const Divider(),
              itemBuilder: (context, idx) {
                final held = list[idx];
                final total = held.items.fold<int>(0, (s, i) => s + i.subtotal);
                return ListTile(
                  title: Text(held.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${held.items.length} item • ${formatRupiah(total)}\n${DateFormatter.formatDateTime(held.heldAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Hapus',
                        onPressed: () => controller.deleteHeldCart(held),
                      ),
                      FilledButton(
                        onPressed: () {
                          Get.back();
                          controller.resumeHeldCart(held);
                        },
                        child: const Text('Lanjutkan'),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Tutup')),
        ],
      ),
    );
  }

  void _showPosSettingsDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Pengaturan Kasir (POS)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle Stok Minus
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Izinkan Stok Minus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Dapat menjual produk meski stok sistem habis (default mati)'),
                  value: controller.allowNegativeStock.value,
                  onChanged: (val) => controller.setAllowNegativeStock(val),
                )),
            const Divider(),

            // Lebar Struk Thermal
            Obx(() => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ukuran Lebar Struk Thermal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${controller.receiptWidth.value} mm'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '58', label: Text('58 mm')),
                      ButtonSegment(value: '80', label: Text('80 mm')),
                    ],
                    selected: {controller.receiptWidth.value},
                    onSelectionChanged: (set) => controller.setReceiptWidth(set.first),
                  ),
                )),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Get.back(), child: const Text('Tutup')),
        ],
      ),
    );
  }
}

class _PaymentRowState {
  String method;
  int amount;
  late final TextEditingController controller;

  _PaymentRowState({
    required this.method,
    required this.amount,
  }) {
    controller = TextEditingController(text: amount > 0 ? amount.toString() : '');
  }

  void updateAmount(int newAmount) {
    amount = newAmount;
    controller.text = newAmount > 0 ? newAmount.toString() : '';
  }
}
