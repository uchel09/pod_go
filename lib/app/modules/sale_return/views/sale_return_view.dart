import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../controllers/sale_return_controller.dart';

class SaleReturnView extends GetView<SaleReturnController> {
  const SaleReturnView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur Penjualan'),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final detail = controller.saleDetail.value;
        if (detail == null) {
          return const Center(
            child: Text('Data transaksi tidak ditemukan atau telah dibatalkan.'),
          );
        }

        final sale = detail.sale;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Info Nota Asal
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                sale.invoiceNo,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Text(
                                  'Selesai',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Waktu: ${DateFormatter.formatDateTime(sale.createdAt)} • Kasir: ${detail.cashierName}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Belanja Asal:'),
                              Text(
                                formatRupiah(sale.total),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Pilih Item Retur
                  Text(
                    'PILIH BARANG & JUMLAH RETUR',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  ...controller.returnableItems.map((row) {
                    final item = row.item.saleItem;
                    final available = row.item.availableQty;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatRupiah(row.netUnitPrice),
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (row.netUnitPrice < item.price)
                                      Text(
                                        formatRupiah(item.price),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Terjual: ${item.qty} | Sudah Diretur: ${row.item.returnedQty} | Tersedia: $available',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: available > 0 ? null : Colors.red,
                              ),
                            ),
                            const Divider(height: 16),

                            // Stepper Qty & Toggle Restock
                            Row(
                              children: [
                                const Text('Jumlah Retur:'),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: row.returnQty.value > 0
                                      ? () => controller.updateQty(
                                          row, row.returnQty.value - 1)
                                      : null,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: theme.colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${row.returnQty.value}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: row.returnQty.value < available
                                      ? () => controller.updateQty(
                                          row, row.returnQty.value + 1)
                                      : null,
                                ),
                              ],
                            ),

                            if (row.returnQty.value > 0) ...[
                              const SizedBox(height: 6),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text('Kembalikan ke Stok Toko',
                                    style: TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  row.restock.value
                                      ? 'Stok produk akan bertambah (+${row.returnQty.value})'
                                      : 'Barang rusak/hilang (stok tidak ditambah)',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                value: row.restock.value,
                                onChanged: (val) =>
                                    controller.toggleRestock(row, val),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),

                  // 3. Form Input Alasan & Metode Refund
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: controller.reasonController,
                            decoration: const InputDecoration(
                              labelText: 'Alasan Retur (Wajib)',
                              hintText: 'Contoh: Barang cacat pabrik / salah ukuran',
                              border: OutlineInputBorder(),
                              helperText: 'Minimal 5 karakter',
                              prefixIcon: Icon(Icons.edit_note),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          const Text('Metode Pengembalian Uang (Refund)',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'cash',
                                label: Text('Tunai (Cash)'),
                                icon: Icon(Icons.money),
                              ),
                              ButtonSegment(
                                value: 'other',
                                label: Text('Lainnya'),
                                icon: Icon(Icons.account_balance_wallet_outlined),
                              ),
                            ],
                            selected: {controller.refundMethod.value},
                            onSelectionChanged: (val) {
                              if (val.isNotEmpty) {
                                controller.refundMethod.value = val.first;
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Ringkasan Pengembalian Dana
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal Barang Retur:'),
                              Text(formatRupiah(controller.subtotalRefund)),
                            ],
                          ),
                          if (controller.taxRefund > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Pajak Dikembalikan:'),
                                Text(formatRupiah(controller.taxRefund)),
                              ],
                            ),
                          ],
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL PENGEMBALIAN (REFUND)',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                formatRupiah(controller.totalRefund),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: (controller.totalReturnedItemCount > 0 &&
                                    !controller.isSaving.value)
                                ? controller.submitReturn
                                : null,
                            icon: const Icon(Icons.assignment_return),
                            label: controller.isSaving.value
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'PROSES RETUR (${controller.totalReturnedItemCount} ITEM)',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
