import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_state.dart';
import '../../../data/repositories/customer_repository.dart';
import '../controllers/customer_detail_controller.dart';

class CustomerDetailView extends GetView<CustomerDetailController> {
  const CustomerDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final name = controller.customerWithBalance.value?.customer.name;
          return Text(name ?? 'Detail Pelanggan');
        }),
        actions: [
          Obx(() {
            final cust = controller.customerWithBalance.value?.customer;
            if (cust == null || !controller.canManage) return const SizedBox.shrink();

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit Pelanggan',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _showEditCustomerDialog(context),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'toggle_status') {
                      controller.toggleActiveStatus();
                    } else if (val == 'delete') {
                      _confirmDelete(context);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle_status',
                      child: Row(
                        children: [
                          Icon(
                            cust.isActive ? Icons.block : Icons.check_circle_outline,
                            size: 18,
                            color: cust.isActive ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(cust.isActive ? 'Nonaktifkan Pelanggan' : 'Aktifkan Pelanggan'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Hapus Pelanggan', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        if (!controller.hasCustomerFeature) {
          return const ErrorState(
            message: 'Fitur Pelanggan & Kasbon terkunci. Silakan upgrade lisensi.',
          );
        }

        if (!controller.canView) {
          return const ErrorState(
            message: 'Akses Ditolak: Anda tidak memiliki izin untuk melihat pelanggan.',
          );
        }

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = controller.customerWithBalance.value;
        if (data == null) {
          return const ErrorState(message: 'Data pelanggan tidak ditemukan.');
        }

        final customer = data.customer;
        final balance = data.balance;
        final hasDebt = balance > 0;
        final remainingCredit = customer.creditLimit != null
            ? (customer.creditLimit! - balance).clamp(0, customer.creditLimit!)
            : null;

        return RefreshIndicator(
          onRefresh: controller.loadCustomerDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kartu Informasi Profil
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: customer.isActive
                                  ? theme.colorScheme.primaryContainer
                                  : Colors.grey.shade300,
                              child: Text(
                                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: customer.isActive
                                      ? theme.colorScheme.onPrimaryContainer
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          customer.name,
                                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: customer.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: customer.isActive ? Colors.green.shade200 : Colors.grey.shade400,
                                          ),
                                        ),
                                        child: Text(
                                          customer.isActive ? 'Aktif' : 'Nonaktif',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: customer.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(customer.phone!, style: theme.textTheme.bodyMedium),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (customer.address != null && customer.address!.isNotEmpty) ...[
                          const Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customer.address!,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (customer.note != null && customer.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.note_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customer.note!,
                                  style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kartu Status Piutang / Kasbon
                Card(
                  elevation: 0,
                  color: hasDebt ? Colors.red.shade50 : Colors.green.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: hasDebt ? Colors.red.shade200 : Colors.green.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: hasDebt ? Colors.red.shade100 : Colors.green.shade100,
                              child: Icon(
                                hasDebt ? Icons.money_off : Icons.check_circle_outline,
                                color: hasDebt ? Colors.red.shade900 : Colors.green.shade900,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hasDebt ? 'Sisa Hutang (Kasbon)' : 'Status Hutang',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: hasDebt ? Colors.red.shade900 : Colors.green.shade900,
                                    ),
                                  ),
                                  Text(
                                    formatRupiah(balance),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                      color: hasDebt ? Colors.red.shade900 : Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (customer.creditLimit != null) ...[
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Batas Limit Kasbon: ${formatRupiah(customer.creditLimit!)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                              Text(
                                'Sisa Limit: ${formatRupiah(remainingCredit ?? 0)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (remainingCredit ?? 0) > 0 ? Colors.black87 : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Tombol Aksi
                        Row(
                          children: [
                            if (controller.canCollect)
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: hasDebt ? Colors.red.shade800 : Colors.grey,
                                  ),
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Terima Pembayaran'),
                                  onPressed: hasDebt ? () => _showPaymentDialog(context, balance) : null,
                                ),
                              ),
                            if (hasDebt) ...[
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Salin Pengingat WhatsApp',
                                icon: const Icon(Icons.share_outlined),
                                onPressed: () => controller.copyWhatsAppReminder(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Buku Pembantu Piutang (Ledger)
                Text(
                  'Buku Pembantu Piutang',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Riwayat transaksi kasbon, pembayaran, dan retur pelanggan.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                if (controller.ledger.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.history_outlined, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          'Belum ada riwayat transaksi piutang untuk pelanggan ini.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: controller.ledger.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = controller.ledger[index];
                        final isDebit = item.debit > 0;
                        final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(item.date);

                        IconData iconData;
                        Color iconColor;
                        String typeLabel;

                        switch (item.type) {
                          case 'credit_sale':
                          case 'credit':
                            iconData = Icons.shopping_cart_checkout;
                            iconColor = Colors.red.shade700;
                            typeLabel = 'Kasbon Penjualan';
                            break;
                          case 'payment':
                            iconData = Icons.payments;
                            iconColor = Colors.green.shade700;
                            typeLabel = 'Pelunasan / Bayar';
                            break;
                          case 'credit_return':
                          case 'return':
                            iconData = Icons.replay;
                            iconColor = Colors.blue.shade700;
                            typeLabel = 'Retur Kasbon';
                            break;
                          default:
                            iconData = Icons.swap_horiz;
                            iconColor = Colors.grey;
                            typeLabel = 'Transaksi';
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: iconColor.withValues(alpha: 0.15),
                            child: Icon(iconData, size: 18, color: iconColor),
                          ),
                          title: Row(
                            children: [
                              Text(
                                typeLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (item.refNo.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '#${item.refNo}',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              if (item.note != null && item.note!.isNotEmpty)
                                Text(item.note!, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isDebit
                                    ? '+ ${formatRupiah(item.debit)}'
                                    : '- ${formatRupiah(item.credit)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
                                ),
                              ),
                              Text(
                                'Saldo: ${formatRupiah(item.balanceAfter)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showPaymentDialog(BuildContext context, int currentBalance) {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(text: currentBalance.toString());
    final noteCtrl = TextEditingController();
    var selectedMethod = 'cash';

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Terima Pembayaran Kasbon'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Hutang Saat Ini:'),
                            Text(
                              formatRupiah(currentBalance),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah Pembayaran (Rp) *',
                          prefixIcon: Icon(Icons.money),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Jumlah pembayaran wajib diisi';
                          }
                          final parsed = int.tryParse(val.trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Jumlah pembayaran harus lebih dari 0';
                          }
                          if (parsed > currentBalance) {
                            return 'Pembayaran tidak boleh melebihi sisa hutang';
                          }
                          return null;
                        },
                        autofocus: true,
                      ),
                      const SizedBox(height: 8),
                      // Quick fill buttons
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Bayar Lunas'),
                            onPressed: () {
                              amountCtrl.text = currentBalance.toString();
                            },
                          ),
                          if (currentBalance >= 20000)
                            ActionChip(
                              label: const Text('50%'),
                              onPressed: () {
                                amountCtrl.text = (currentBalance ~/ 2).toString();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Metode Pembayaran:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMethod,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Tunai (Cash)')),
                          DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank')),
                          DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedMethod = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (Opsional)',
                          hintText: 'Misal: Cicilan ke-1 / Titip kasir',
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
                    final amount = int.parse(amountCtrl.text.trim());
                    Get.back();
                    await controller.recordPayment(
                      amount: amount,
                      method: selectedMethod,
                      note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                    );
                  }
                },
                child: const Text('Konfirmasi Bayar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCustomerDialog(BuildContext context) {
    final cust = controller.customerWithBalance.value?.customer;
    if (cust == null) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: cust.name);
    final phoneCtrl = TextEditingController(text: cust.phone ?? '');
    final addressCtrl = TextEditingController(text: cust.address ?? '');
    final noteCtrl = TextEditingController(text: cust.note ?? '');
    final limitCtrl = TextEditingController(
      text: cust.creditLimit != null ? cust.creditLimit.toString() : '',
    );

    Get.dialog(
      AlertDialog(
        title: const Text('Edit Pelanggan'),
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
                await controller.updateCustomer(
                  UpdateCustomerInput(
                    id: cust.id,
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                    address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                    note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                    creditLimit: limit,
                    isActive: cust.isActive,
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

  void _confirmDelete(BuildContext context) async {
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Hapus Pelanggan?',
      message: 'Pelanggan hanya dapat dihapus jika belum memiliki transaksi sama sekali. Lanjutkan?',
      confirmText: 'Hapus',
      isDestructive: true,
    );
    if (confirmed) {
      controller.deleteCustomer();
    }
  }
}
