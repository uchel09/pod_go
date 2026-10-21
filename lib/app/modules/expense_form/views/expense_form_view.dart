import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/expense_form_controller.dart';

class ExpenseFormView extends GetView<ExpenseFormController> {
  const ExpenseFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEEE, dd MMMM yyyy, HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          controller.isEditMode ? 'Ubah Pengeluaran' : 'Catat Pengeluaran',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        controller.isEditMode
                            ? 'Perbarui Data Biaya Operasional'
                            : 'Form Pengeluaran Operasional Toko',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Semua pengeluaran yang dicatat akan memotong laba kotor di laporan keuangan.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 1. Pemilihan Tanggal
                      Obx(() {
                        String dateStr;
                        try {
                          dateStr = dateFmt.format(
                            controller.selectedDate.value.toLocal(),
                          );
                        } catch (_) {
                          dateStr = DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(controller.selectedDate.value.toLocal());
                        }
                        return InkWell(
                          onTap: () => controller.pickDate(context),
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Tanggal Pengeluaran *',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                              isDense: true,
                            ),
                            child: Text(
                              dateStr,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),

                      // 2. Kategori Pengeluaran + Tambah Cepat
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Obx(() {
                              if (controller.isLoadingCategories.value) {
                                return const LinearProgressIndicator();
                              }
                              return DropdownButtonFormField<int?>(
                                initialValue: controller.selectedCategoryId.value,
                                decoration: const InputDecoration(
                                  labelText: 'Kategori Pengeluaran *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                isExpanded: true,
                                items: controller.categories.map((c) {
                                  return DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(c.name),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    controller.selectedCategoryId.value = val;
                                  }
                                },
                                validator: (val) => val == null
                                    ? 'Kategori wajib dipilih'
                                    : null,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Tambah Kategori Baru',
                            icon: const Icon(Icons.add),
                            onPressed: () =>
                                _showQuickAddCategoryDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 3. Nominal Pengeluaran
                      TextFormField(
                        controller: controller.amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Nominal Biaya (Rupiah) *',
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '0',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Nominal pengeluaran wajib diisi';
                          }
                          final parsed =
                              int.tryParse(
                                val.replaceAll(RegExp(r'[^0-9]'), ''),
                              ) ??
                              0;
                          if (parsed <= 0) {
                            return 'Nominal harus lebih besar dari Rp 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 4. Metode Pembayaran
                      Text(
                        'Metode Pembayaran',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Obx(
                        () => SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'cash',
                              label: Text('Tunai'),
                              icon: Icon(Icons.payments_outlined),
                            ),
                            ButtonSegment(
                              value: 'transfer',
                              label: Text('Transfer'),
                              icon: Icon(Icons.account_balance_outlined),
                            ),
                            ButtonSegment(
                              value: 'other',
                              label: Text('Lainnya'),
                              icon: Icon(Icons.credit_card),
                            ),
                          ],
                          selected: {controller.selectedPaymentMethod.value},
                          onSelectionChanged: (set) {
                            controller.selectedPaymentMethod.value = set.first;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. Catatan / Keterangan
                      TextFormField(
                        controller: controller.noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Catatan / Keterangan (Opsional)',
                          hintText:
                              'Contoh: Token listrik toko 100rb, sewa ruko bulan Mei',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tombol Simpan
                      Obx(
                        () => FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: controller.isSaving.value
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            controller.isSaving.value
                                ? 'Menyimpan...'
                                : (controller.isEditMode
                                      ? 'Simpan Perubahan'
                                      : 'Catat Pengeluaran'),
                          ),
                          onPressed: controller.isSaving.value
                              ? null
                              : controller.save,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickAddCategoryDialog(BuildContext context) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Kategori Baru'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
            hintText: 'Contoh: Promosi & Iklan',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                controller.quickAddCategory(name);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
