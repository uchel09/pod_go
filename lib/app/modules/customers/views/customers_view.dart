import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_state.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../routes/app_pages.dart';
import '../controllers/customers_controller.dart';

class CustomersView extends GetView<CustomersController> {
  const CustomersView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan & Kasbon'),
        actions: [
          IconButton(
            tooltip: 'Segarkan Data',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.loadInitialData(),
          ),
        ],
      ),
      floatingActionButton: Obx(() {
        if (!controller.hasCustomerFeature || !controller.canManage) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton.extended(
          onPressed: () => _showAddCustomerDialog(context),
          icon: const Icon(Icons.person_add),
          label: const Text('Tambah Pelanggan'),
        );
      }),
      body: Obx(() {
        if (!controller.hasCustomerFeature) {
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
                        'Fitur Pelanggan & Kasbon Terkunci',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pencatatan data pelanggan, penjualan hutang/kasbon, batas limit piutang, dan pelunasan hanya tersedia pada lisensi Semi-Premium ke atas.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Upgrade ke Semi-Premium'),
                        onPressed: () => FeatureGate.to.requireFeature(Feature.customerCredit),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (!controller.canView) {
          return const ErrorState(
            message: 'Akses Ditolak: Anda tidak memiliki izin untuk melihat data pelanggan.',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.loadInitialData,
          child: Column(
            children: [
              // Ringkasan Piutang & Pencarian
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: Column(
                  children: [
                    // Kartu Total Piutang
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, color: Colors.amber.shade900, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Sisa Piutang Toko',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatRupiah(controller.totalReceivables.value),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Search bar & Filter chip
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller.searchController,
                            onChanged: controller.onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Cari nama atau no. telepon...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: controller.searchQuery.value.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        controller.searchController.clear();
                                        controller.onSearchChanged('');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Punya Hutang'),
                          selected: controller.onlyWithDebt.value,
                          onSelected: (_) => controller.toggleOnlyWithDebt(),
                          avatar: controller.onlyWithDebt.value
                              ? const Icon(Icons.check, size: 16)
                              : const Icon(Icons.money_off, size: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Daftar Pelanggan
              Expanded(
                child: controller.isLoading.value
                    ? const Center(child: CircularProgressIndicator())
                    : controller.customers.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
                                  const SizedBox(height: 16),
                                  Text(
                                    controller.searchQuery.value.isNotEmpty
                                        ? 'Tidak ditemukan pelanggan yang cocok'
                                        : controller.onlyWithDebt.value
                                            ? 'Tidak ada pelanggan yang memiliki sisa hutang'
                                            : 'Belum ada data pelanggan',
                                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 8),
                                  if (controller.canManage && controller.searchQuery.value.isEmpty && !controller.onlyWithDebt.value)
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.person_add),
                                      label: const Text('Tambah Pelanggan Baru'),
                                      onPressed: () => _showAddCustomerDialog(context),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: controller.customers.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = controller.customers[index];
                              final customer = item.customer;
                              final balance = item.balance;
                              final hasDebt = balance > 0;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: customer.isActive
                                      ? (hasDebt ? Colors.red.shade100 : theme.colorScheme.primaryContainer)
                                      : Colors.grey.shade300,
                                  child: Text(
                                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: customer.isActive
                                          ? (hasDebt ? Colors.red.shade900 : theme.colorScheme.onPrimaryContainer)
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        customer.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: customer.isActive ? null : Colors.grey,
                                          decoration: customer.isActive ? null : TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ),
                                    if (!customer.isActive) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('Nonaktif', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    if (customer.phone != null && customer.phone!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(customer.phone!, style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    if (customer.creditLimit != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Limit Kasbon: ${formatRupiah(customer.creditLimit!)}',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatRupiah(balance),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
                                      ),
                                    ),
                                    Text(
                                      hasDebt ? 'Sisa Hutang' : 'Lunas',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: hasDebt ? Colors.red.shade400 : Colors.green.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  final result = await Get.toNamed(
                                    Routes.CUSTOMER_DETAIL,
                                    arguments: customer.id,
                                  );
                                  if (result == true) {
                                    controller.loadInitialData();
                                  }
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showAddCustomerDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final limitCtrl = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('Tambah Pelanggan Baru'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pelanggan *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Nama pelanggan wajib diisi';
                      }
                      return null;
                    },
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'No. Telepon / WhatsApp',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Batas Limit Hutang (Rp)',
                      hintText: 'Kosongkan jika tanpa batas',
                      prefixIcon: Icon(Icons.credit_card_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alamat',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Catatan',
                      prefixIcon: Icon(Icons.note_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final limit = limitCtrl.text.trim().isNotEmpty
                    ? int.tryParse(limitCtrl.text.trim())
                    : null;
                Get.back();
                await controller.createCustomer(
                  CreateCustomerInput(
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                    address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                    note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                    creditLimit: limit,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
