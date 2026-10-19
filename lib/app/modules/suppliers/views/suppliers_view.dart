import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../data/local/app_database.dart';
import '../controllers/suppliers_controller.dart';

class SuppliersView extends GetView<SuppliersController> {
  const SuppliersView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Supplier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: controller.loadSuppliers,
          ),
        ],
      ),
      floatingActionButton: controller.canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showSupplierDialog(context),
              icon: const Icon(Icons.add_business),
              label: const Text('Tambah Supplier'),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: controller.searchController,
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Cari nama supplier, telepon, atau alamat...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Obx(() => controller.searchQuery.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.searchController.clear();
                              controller.onSearchChanged('');
                            },
                          )
                        : const SizedBox.shrink()),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                ),
              ),

              // Content List
              Expanded(
                child: Obx(() {
                  if (controller.isLoading.value) {
                    return const LoadingIndicator(message: 'Memuat data supplier...');
                  }

                  if (controller.suppliers.isEmpty) {
                    return EmptyState(
                      title: controller.searchQuery.value.isEmpty
                          ? 'Belum Ada Supplier'
                          : 'Supplier Tidak Ditemukan',
                      message: controller.searchQuery.value.isEmpty
                          ? 'Daftarkan data supplier/pemasok barang untuk toko Anda.'
                          : 'Tidak ada supplier yang cocok dengan kata kunci "${controller.searchQuery.value}".',
                      icon: Icons.storefront_outlined,
                      action: controller.canManage && controller.searchQuery.value.isEmpty
                          ? FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah Supplier Pertama'),
                              onPressed: () => _showSupplierDialog(context),
                            )
                          : null,
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: 8,
                    ),
                    itemCount: controller.suppliers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final supplier = controller.suppliers[idx];
                      return _buildSupplierCard(context, theme, supplier);
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierCard(BuildContext context, ThemeData theme, Supplier supplier) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.business_outlined, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(
          supplier.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplier.phone != null && supplier.phone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(supplier.phone!, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            if (supplier.address != null && supplier.address!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supplier.address!,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: controller.canManage
            ? PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'edit') {
                    _showSupplierDialog(context, supplierToEdit: supplier);
                  } else if (val == 'delete') {
                    _handleDeleteSupplier(context, supplier);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit Supplier'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Hapus', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  void _showSupplierDialog(BuildContext context, {Supplier? supplierToEdit}) {
    final isEdit = supplierToEdit != null;
    final nameController = TextEditingController(text: supplierToEdit?.name ?? '');
    final phoneController = TextEditingController(text: supplierToEdit?.phone ?? '');
    final addressController = TextEditingController(text: supplierToEdit?.address ?? '');
    final formKey = GlobalKey<FormState>();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEdit ? 'Edit Data Supplier' : 'Tambah Supplier Baru',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Supplier / Pemasok *',
                      hintText: 'Misal: PT Sumber Makmur',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Nama supplier wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Telepon / WhatsApp (Opsional)',
                      hintText: 'Contoh: 081234567890',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(
                      labelText: 'Alamat / Keterangan (Opsional)',
                      hintText: 'Contoh: Jl. Sudirman No. 10',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('Batal'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          bool success;
                          if (isEdit) {
                            success = await controller.updateSupplier(
                              id: supplierToEdit.id,
                              name: nameController.text.trim(),
                              phone: phoneController.text.trim(),
                              address: addressController.text.trim(),
                            );
                          } else {
                            success = await controller.createSupplier(
                              name: nameController.text.trim(),
                              phone: phoneController.text.trim(),
                              address: addressController.text.trim(),
                            );
                          }
                          if (success) {
                            Get.back();
                          }
                        },
                        child: Text(isEdit ? 'Simpan' : 'Tambah'),
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

  Future<void> _handleDeleteSupplier(BuildContext context, Supplier supplier) async {
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Hapus Supplier',
      message:
          'Apakah Anda yakin ingin menghapus supplier "${supplier.name}"?\n\nJika supplier ini sudah memiliki riwayat pembelian, penghapusan akan ditolak demi menjaga keutuhan data transaksi.',
      confirmText: 'Hapus',
      isDestructive: true,
    );

    if (confirmed) {
      await controller.deleteSupplier(supplier);
    }
  }
}
