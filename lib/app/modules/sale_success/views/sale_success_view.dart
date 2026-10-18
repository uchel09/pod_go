import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../controllers/sale_success_controller.dart';

class SaleSuccessView extends GetView<SaleSuccessController> {
  const SaleSuccessView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          controller.newTransaction();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): controller.newTransaction,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Transaksi Selesai'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Tutup / Transaksi Baru (Esc)',
                  icon: const Icon(Icons.close),
                  onPressed: controller.newTransaction,
                ),
              ],
            ),
            body: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: LoadingIndicator(message: 'Memuat data transaksi...'));
              }

              final detail = controller.saleDetail.value;
              if (detail == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Data transaksi tidak ditemukan.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: controller.newTransaction,
                        child: const Text('KEMBALI KE KASIR'),
                      ),
                    ],
                  ),
                );
              }

              final sale = detail.sale;
              final autoStatus = controller.autoPrintStatus.value;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Header Sukses
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.green,
                            child: Icon(Icons.check, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Transaksi Berhasil!',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${sale.invoiceNo} • ${DateFormatter.formatDateTime(sale.createdAt)}',
                                  style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
                                ),
                                Text(
                                  'Kasir: ${detail.cashierName}',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Status Auto-Print bila ada
                      if (autoStatus != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: autoStatus.contains('berhasil')
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: autoStatus.contains('berhasil')
                                  ? Colors.green.shade200
                                  : Colors.orange.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                autoStatus.contains('berhasil')
                                    ? Icons.check_circle_outline
                                    : Icons.print_outlined,
                                size: 18,
                                color: autoStatus.contains('berhasil')
                                    ? Colors.green.shade800
                                    : Colors.orange.shade900,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  autoStatus,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: autoStatus.contains('berhasil')
                                        ? Colors.green.shade900
                                        : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Card Kembalian (Besar dan Jelas)
                      Card(
                        elevation: 0,
                        color: Colors.green.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.green.shade300),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'KEMBALIAN',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatRupiah(sale.change),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Rincian Pembayaran
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildSummaryRow('Total Tagihan', formatRupiah(sale.total), isBold: true),
                              const SizedBox(height: 8),
                              _buildSummaryRow('Total Dibayar', formatRupiah(sale.paid)),
                              if (sale.discount > 0) ...[
                                const SizedBox(height: 8),
                                _buildSummaryRow('Total Diskon', '-${formatRupiah(sale.discount)}', color: Colors.orange.shade800),
                              ],
                              const Divider(height: 20),
                              // Metode Bayar
                              ...detail.payments.map((p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: _buildSummaryRow(
                                      'Metode: ${p.method.toUpperCase()}',
                                      formatRupiah(p.amount),
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Daftar Item Ringkas
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
                              Text(
                                'Item Belanja (${detail.items.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Divider(height: 16),
                              ...detail.items.map((item) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.productName,
                                            style: const TextStyle(fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${item.qty} x ${formatRupiah(item.price)}',
                                          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          formatRupiah(item.subtotal),
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tombol Aksi Struk
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: controller.isSavingPdf.value ? null : controller.savePdf,
                              icon: controller.isSavingPdf.value
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.picture_as_pdf, size: 20),
                              label: const Text('Simpan PDF'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: controller.isPrinting.value ? null : controller.printReceipt,
                              icon: controller.isPrinting.value
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.print, size: 20),
                              label: const Text('Cetak Struk'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Tombol Selesai / Transaksi Baru
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: controller.newTransaction,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text(
                          'TRANSAKSI BARU (ESC)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
