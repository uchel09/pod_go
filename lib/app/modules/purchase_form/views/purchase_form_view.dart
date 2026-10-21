import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/local/app_database.dart';
import '../../../routes/app_pages.dart';
import '../controllers/purchase_form_controller.dart';

class PurchaseFormView extends GetView<PurchaseFormController> {
  const PurchaseFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Penerimaan Barang (Pembelian)'),
        actions: [
          Obx(() => controller.items.isNotEmpty
              ? TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
                  label: const Text('Kosongkan', style: TextStyle(color: Colors.red)),
                  onPressed: () => _handleClearDraft(context),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Form: Supplier, RefNo, Tanggal
              _buildFormHeader(context, theme, isMobile),

              // Action Toolbar: Tambah Produk, Scan Kamera
              _buildItemActionToolbar(context, theme),

              const Divider(height: 1),

              // Daftar Barang Pembelian
              Expanded(
                child: Obx(() {
                  if (controller.items.isEmpty) {
                    return EmptyState(
                      title: 'Daftar Barang Masih Kosong',
                      message: 'Tambahkan produk lewat pencarian nama atau scan barcode (HID scanner / kamera).',
                      icon: Icons.add_shopping_cart_outlined,
                      action: FilledButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('Pilih Produk Toko'),
                        onPressed: () => _showProductSearchDialog(context),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: 8,
                    ),
                    itemCount: controller.items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = controller.items[idx];
                      return _buildCartItemCard(context, theme, item, isMobile);
                    },
                  );
                }),
              ),

              // Bottom Summary & Simpan
              _buildBottomSummaryBar(context, theme, isMobile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormHeader(BuildContext context, ThemeData theme, bool isMobile) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Row(
              children: [
                // Pilih Supplier (Opsional)
                Expanded(
                  flex: 3,
                  child: Obx(() {
                    return DropdownButtonFormField<int?>(
                      initialValue: controller.selectedSupplierId.value,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Supplier / Pemasok (Opsional)',
                        hintText: 'Pemasok Umum',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        prefixIcon: const Icon(Icons.business_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          tooltip: 'Kelola Supplier',
                          onPressed: () => Get.toNamed(Routes.SUPPLIERS),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Pemasok Umum (Tanpa Supplier)'),
                        ),
                        ...controller.suppliers.map((s) => DropdownMenuItem<int?>(
                              value: s.id,
                              child: Text(s.name, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) => controller.selectedSupplierId.value = val,
                    );
                  }),
                ),
                const SizedBox(width: 10),

                // No. Faktur / Ref (Opsional)
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: controller.refNoController,
                    decoration: const InputDecoration(
                      labelText: 'No. Faktur / Ref (Opsional)',
                      hintText: 'Otomatis (PO-...)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      prefixIcon: Icon(Icons.tag, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Tanggal Pembelian
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Obx(() {
                      final dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID')
                          .format(controller.purchaseDate.value);
                      return Text('Tanggal: $dateStr', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500));
                    }),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: controller.purchaseDate.value,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      controller.purchaseDate.value = picked;
                    }
                  },
                  child: const Text('Ubah Tanggal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemActionToolbar(BuildContext context, ThemeData theme) {
    final isAndroid = Platform.isAndroid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Cari & Tambah Produk'),
              onPressed: () => _showProductSearchDialog(context),
            ),
          ),
          if (isAndroid) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan Kamera Android',
              onPressed: controller.scanWithCamera,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
    BuildContext context,
    ThemeData theme,
    PurchaseCartItem item,
    bool isMobile,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Product Name & Remove Button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Stok saat ini: ${item.product.currentStock} | Harga beli lama: ${formatRupiah(item.product.costPrice)}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => controller.removeItem(item),
                ),
              ],
            ),
            const Divider(height: 14),

            // Row 2: Inputs Qty, CostPrice & Subtotal
            Row(
              children: [
                // Qty Controller (- / +)
                Row(
                  children: [
                    IconButton.outlined(
                      icon: const Icon(Icons.remove, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => controller.updateItemQty(item, item.qty.value - 1),
                    ),
                    Obx(() => Container(
                          constraints: const BoxConstraints(minWidth: 36),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '${item.qty.value}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        )),
                    IconButton.outlined(
                      icon: const Icon(Icons.add, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => controller.updateItemQty(item, item.qty.value + 1),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Harga Beli Input
                Expanded(
                  child: TextFormField(
                    initialValue: '${item.costPrice.value}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Harga Beli (Rp)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      prefixText: 'Rp ',
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      controller.updateItemCostPrice(item, parsed);
                    },
                  ),
                ),
                const SizedBox(width: 14),

                // Subtotal
                Obx(() => Text(
                      formatRupiah(item.subtotal),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: theme.colorScheme.primary,
                      ),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSummaryBar(BuildContext context, ThemeData theme, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toggle Pembaruan Harga Beli
          Obx(() => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Perbarui harga beli master produk ke harga ini',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: const Text(
                  'Jika aktif, harga beli (HPP) di katalog produk akan otomatis disesuaikan.',
                  style: TextStyle(fontSize: 11),
                ),
                value: controller.updateCostPrice.value,
                onChanged: (val) => controller.updateCostPrice.value = val,
              )),
          const SizedBox(height: 10),

          // Total Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total (${controller.totalItemCount} Barang):',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        formatRupiah(controller.totalAmount),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  )),
              Obx(() => FilledButton.icon(
                    icon: controller.isSaving.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(controller.isSaving.value ? 'Menyimpan...' : 'Simpan Pembelian'),
                    onPressed: controller.isSaving.value
                        ? null
                        : () => _handleConfirmSave(context),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  void _showProductSearchDialog(BuildContext context) {
    final searchCtrl = TextEditingController();
    final filtered = <Product>[].obs;
    filtered.value = controller.allProducts;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pilih Produk Pembelian',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Ketik nama produk atau barcode...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final term = val.trim().toLowerCase();
                    if (term.isEmpty) {
                      filtered.value = controller.allProducts;
                    } else {
                      filtered.value = controller.allProducts.where((p) {
                        return p.name.toLowerCase().contains(term) ||
                            (p.barcode != null && p.barcode!.toLowerCase().contains(term));
                      }).toList();
                    }
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Obx(() {
                    if (filtered.isEmpty) {
                      return const Center(child: Text('Tidak ada produk yang cocok.'));
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final product = filtered[idx];
                        final isInactive = !product.isActive;

                        return ListTile(
                          title: Text(
                            product.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isInactive ? Colors.grey : null,
                            ),
                          ),
                          subtitle: Text(
                            'Stok: ${product.currentStock} | HPP: ${formatRupiah(product.costPrice)}${isInactive ? ' (Nonaktif)' : ''}',
                            style: TextStyle(fontSize: 12, color: isInactive ? Colors.red : Colors.grey),
                          ),
                          trailing: isInactive
                              ? const Chip(label: Text('Nonaktif', style: TextStyle(fontSize: 10)))
                              : const Icon(Icons.add_circle_outline, color: Colors.blue),
                          onTap: () async {
                            Get.back();
                            await controller.addProduct(product);
                          },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleConfirmSave(BuildContext context) async {
    final costChanges = controller.getCostPriceChanges();

    if (costChanges.isNotEmpty && controller.updateCostPrice.value) {
      // Tampilkan konfirmasi perubahan harga beli produk sebelum simpan
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konfirmasi Pembelian & Harga Beli'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pembaruan harga beli aktif. Harga beli produk berikut akan diperbarui di katalog master:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  ...costChanges.map((c) {
                    final diff = c['diff'] as int;
                    final diffStr = diff > 0 ? '+${formatRupiah(diff)}' : formatRupiah(diff);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              c['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${formatRupiah(c['oldCost'] as int)} -> ${formatRupiah(c['newCost'] as int)} ($diffStr)',
                            style: TextStyle(
                              fontSize: 12,
                              color: diff > 0 ? Colors.green.shade700 : Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text(
                    'Simpan transaksi penerimaan barang sekarang?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan Pembelian'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    await controller.savePurchase();
  }

  Future<void> _handleClearDraft(BuildContext context) async {
    final confirm = await ConfirmDialog.show(
      context: context,
      title: 'Kosongkan Draft',
      message: 'Apakah Anda yakin ingin menghapus seluruh daftar barang di form pembelian ini?',
      confirmText: 'Kosongkan',
      isDestructive: true,
    );

    if (confirm) {
      controller.clearDraft();
    }
  }
}
