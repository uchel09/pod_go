import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/import_models.dart';
import '../controllers/import_wizard_controller.dart';

class ImportWizardView extends GetView<ImportWizardController> {
  const ImportWizardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final typeName = controller.selectedType.value.displayName;
          return Text('Wizard Impor $typeName');
        }),
        centerTitle: false,
      ),
      body: Obx(() {
        final step = controller.currentStep.value;

        return Column(
          children: [
            // STEPPER HEADER
            _buildStepperHeader(context, step),
            const Divider(height: 1),

            // STEPPER CONTENT
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: _buildStepContent(context, step),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStepperHeader(BuildContext context, int currentStep) {
    final theme = Theme.of(context);
    final steps = [
      'Pilih Berkas',
      'Pemetaan Kolom',
      'Preview & Validasi',
      'Eksekusi Batch',
      'Selesai',
    ];

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final prevStep = index ~/ 2;
            final isPassed = currentStep > prevStep;
            return Expanded(
              child: Container(
                height: 2,
                color: isPassed ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final isActive = currentStep == stepIndex;
          final isDone = currentStep > stepIndex;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isDone
                    ? theme.colorScheme.primary
                    : isActive
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                child: isDone
                    ? Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary)
                    : Text(
                        '${stepIndex + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.outline,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                steps[stepIndex],
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, int step) {
    switch (step) {
      case 0:
        return _buildStep0PickFile(context);
      case 1:
        return _buildStep1ColumnMapping(context);
      case 2:
        return _buildStep2PreviewAndOptions(context);
      case 3:
        return _buildStep3Execution(context);
      case 4:
        return _buildStep4Summary(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // =========================================================================
  // LANGKAH 0: PILIH BERKAS
  // =========================================================================

  Widget _buildStep0PickFile(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '1. Pilih Jenis Data & Berkas',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Tentukan jenis entitas data yang ingin diimpor dan pilih berkas berformat .CSV atau .XLSX / .XLS.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Pilihan Jenis Entitas
          Text('JENIS DATA IMPOR', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Obx(() {
            return SegmentedButton<ImportTemplateType>(
              segments: const [
                ButtonSegment(
                  value: ImportTemplateType.product,
                  label: Text('Produk'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: ImportTemplateType.category,
                  label: Text('Kategori'),
                  icon: Icon(Icons.category_outlined),
                ),
                ButtonSegment(
                  value: ImportTemplateType.supplier,
                  label: Text('Supplier'),
                  icon: Icon(Icons.business_outlined),
                ),
              ],
              selected: {controller.selectedType.value},
              onSelectionChanged: (newSelection) {
                if (newSelection.isNotEmpty) {
                  controller.setImportType(newSelection.first);
                }
              },
            );
          }),
          const SizedBox(height: 24),

          // Dropzone / File Picker Card
          Obx(() {
            final fileName = controller.selectedFileName.value;
            final isParsing = controller.isParsingFile.value;

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: fileName.isNotEmpty ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  width: fileName.isNotEmpty ? 1.5 : 1,
                ),
              ),
              color: fileName.isNotEmpty
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
                  : theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.upload_file, size: 36, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                    if (fileName.isEmpty) ...[
                      Text(
                        'Pilih Berkas Spreadsheet untuk Diimpor',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mendukung format CSV (.csv) dan Microsoft Excel (.xlsx, .xls)',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: isParsing ? null : () => controller.pickFile(),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Jelajahi Berkas (Browse)'),
                      ),
                    ] else ...[
                      Text(
                        fileName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ukuran: ${controller.fileSizeFormatted.value} | ${controller.parsedFileRows.length} baris data ditemukan',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: isParsing ? null : () => controller.pickFile(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Ganti Berkas'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: isParsing ? null : () => controller.currentStep.value = 1,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Lanjut ke Pemetaan Kolom'),
                          ),
                        ],
                      ),
                    ],
                    if (isParsing) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Sedang membaca & menganalisis berkas...'),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // =========================================================================
  // LANGKAH 1: PEMETAAN KOLOM
  // =========================================================================

  Widget _buildStep1ColumnMapping(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2. Pemetaan Kolom Data',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cocokkan kolom tabel POS Me dengan nama kolom pada berkas yang Anda unggah.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () => controller.currentStep.value = 0,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Pilih Berkas Lain'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Info Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kolom telah dicocokkan otomatis berdasarkan kesamaan nama. Anda dapat mengubah pilihan dropdown di bawah bila terdapat nama kolom yang berbeda.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mapping Table
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Obx(() {
              final keys = controller.targetFields.keys.toList();
              final available = controller.availableFileHeaders.toList();

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: keys.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final targetKey = keys[index];
                  final targetLabel = controller.targetFields[targetKey]!;
                  final isRequired = targetLabel.contains('*');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Text(
                                targetLabel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isRequired ? theme.colorScheme.primary : null,
                                ),
                              ),
                              if (isRequired)
                                const Text(
                                  ' (Wajib)',
                                  style: TextStyle(fontSize: 11, color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_right_alt, color: Colors.grey),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: Obx(() {
                            final currentVal = controller.columnMapping[targetKey]?.value;

                            return DropdownButtonFormField<String>(
                              initialValue: currentVal != null && available.contains(currentVal)
                                  ? currentVal
                                  : null,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                hintText: '-- Jangan Petakan / Kosongkan --',
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(
                                    '-- Jangan Petakan --',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                                ...available.map((header) {
                                  return DropdownMenuItem<String>(
                                    value: header,
                                    child: Text(header, overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                controller.columnMapping[targetKey]?.value = val;
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: () => controller.confirmMappingAndProceedToPreview(),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Lanjut ke Preview Data'),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // LANGKAH 2: PREVIEW & VALIDASI
  // =========================================================================

  Widget _buildStep2PreviewAndOptions(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header & Tab Counters
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3. Preview & Validasi Data',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Periksa baris data sebelum dieksekusi ke database POS Me.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => controller.currentStep.value = 1,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Ubah Pemetaan'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Stats Filter Chips & Search
        Row(
          children: [
            Obx(() {
              final tab = controller.filterTab.value;
              final total = controller.totalRowsCount;
              final valid = controller.validRowsCount;
              final error = controller.errorRowsCount;

              return Row(
                children: [
                  ChoiceChip(
                    label: Text('Semua ($total)'),
                    selected: tab == 'semua',
                    onSelected: (_) => controller.filterTab.value = 'semua',
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Valid ($valid)'),
                    selected: tab == 'valid',
                    avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    onSelected: (_) => controller.filterTab.value = 'valid',
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Error ($error)'),
                    selected: tab == 'error',
                    avatar: const Icon(Icons.cancel, size: 16, color: Colors.red),
                    onSelected: (_) => controller.filterTab.value = 'error',
                  ),
                ],
              );
            }),
            const Spacer(),
            SizedBox(
              width: 250,
              height: 40,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Cari nama / barcode...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) => controller.searchQuery.value = val,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Table Preview
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Obx(() {
              if (controller.isValidating.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final rows = controller.filteredPreviewRows;
              if (rows.isEmpty) {
                return const Center(
                  child: Text('Tidak ada baris data yang cocok dengan filter.'),
                );
              }

              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final raw = row.rawValues;
                  final parsed = row.parsedValues;

                  return Container(
                    color: !row.isValid
                        ? Colors.red.withValues(alpha: 0.06)
                        : row.isUpdate
                            ? Colors.amber.withValues(alpha: 0.06)
                            : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Nomor baris
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${row.fileLineNumber}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Nama
                            Expanded(
                              flex: 3,
                              child: Text(
                                (raw['nama'] ?? '-').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Barcode / SKU
                            Expanded(
                              flex: 2,
                              child: Text(
                                (raw['barcode'] ?? raw['sku'] ?? '-').toString(),
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Harga Jual
                            if (controller.selectedType.value == ImportTemplateType.product)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  parsed['sellPrice'] != null
                                      ? formatRupiah(parsed['sellPrice'] as int)
                                      : (raw['harga_jual'] ?? '-').toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),

                            // Stok Awal
                            if (controller.selectedType.value == ImportTemplateType.product)
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'Stok: ${parsed['initialStock'] ?? raw['stok_awal'] ?? 0}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),

                            // Badge Status
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: !row.isValid
                                    ? Colors.red.shade100
                                    : row.isUpdate
                                        ? Colors.amber.shade100
                                        : Colors.green.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                !row.isValid
                                    ? 'Error'
                                    : row.isUpdate
                                        ? 'Update'
                                        : 'Baru',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: !row.isValid
                                      ? Colors.red.shade800
                                      : row.isUpdate
                                          ? Colors.amber.shade900
                                          : Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Error Details or Warnings
                        if (row.errors.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.error_outline, size: 14, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  row.errorSummary!,
                                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (row.warnings.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Colors.amber.shade800),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  row.warnings.join('; '),
                                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // OPSI IMPOR & EKSEKUSI
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Obx(() {
              final opts = controller.options.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'PENGATURAN & ATURAN IMPOR',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Mode Impor
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChoiceChip(
                            label: const Text('Perbarui Data (Upsert)'),
                            selected: opts.mode == ImportMode.upsert,
                            onSelected: (selected) {
                              if (selected) {
                                controller.updateOptions(opts.copyWith(mode: ImportMode.upsert));
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Tambah Baru Saja'),
                            selected: opts.mode == ImportMode.insertOnly,
                            onSelected: (selected) {
                              if (selected) {
                                controller.updateOptions(opts.copyWith(mode: ImportMode.insertOnly));
                              }
                            },
                          ),
                        ],
                      ),

                      // Auto create category & unit
                      if (controller.selectedType.value == ImportTemplateType.product) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: opts.autoCreateCategory,
                              onChanged: (val) {
                                controller.updateOptions(
                                  opts.copyWith(
                                    autoCreateCategory: val ?? true,
                                    autoCreateUnit: val ?? true,
                                  ),
                                );
                              },
                            ),
                            const Text('Buat Kategori/Satuan otomatis'),
                          ],
                        ),

                        // Koreksi stok
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: opts.correctStock,
                              onChanged: (val) {
                                controller.updateOptions(opts.copyWith(correctStock: val ?? false));
                              },
                            ),
                            const Text('Koreksi stok produk yang sudah ada'),
                          ],
                        ),
                      ],

                      // Error Handling
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: opts.skipErrorRows,
                            onChanged: (val) {
                              controller.updateOptions(opts.copyWith(skipErrorRows: val ?? true));
                            },
                          ),
                          const Text('Lewati baris error (lanjutkan data valid)'),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Action Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Obx(() {
              final valid = controller.validRowsCount;
              final err = controller.errorRowsCount;
              final skipText = err > 0 ? ' ($err baris akan dilewati)' : '';
              return Text(
                'Siap mengimpor $valid data valid$skipText',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              );
            }),
            Obx(() {
              final valid = controller.validRowsCount;
              return FilledButton.icon(
                onPressed: valid > 0 ? () => controller.startImportExecution() : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text('Mulai Impor ($valid Data Valid)'),
              );
            }),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // LANGKAH 3: EKSEKUSI BATCH
  // =========================================================================

  Widget _buildStep3Execution(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Sedang Melakukan Impor Data...',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Obx(() => Text(
                    controller.progressMessage.value,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  )),
              const SizedBox(height: 20),
              SizedBox(
                width: 400,
                child: Obx(() {
                  final total = controller.progressTotal.value;
                  final current = controller.progressCurrent.value;
                  final value = total > 0 ? (current / total) : null;
                  return LinearProgressIndicator(value: value, minHeight: 8);
                }),
              ),
              const SizedBox(height: 12),
              const Text(
                'Eksekusi dilakukan per batch (~200 baris) dalam transaksi atomik SQLite Drift.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // LANGKAH 4: RINGKASAN HASIL
  // =========================================================================

  Widget _buildStep4Summary(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final res = controller.summary.value;
      if (res == null) return const SizedBox.shrink();

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Header Icon
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.green.shade100,
              child: Icon(Icons.check_circle, size: 48, color: Colors.green.shade700),
            ),
            const SizedBox(height: 16),
            Text(
              'Impor Selesai!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Data berhasil diproses dan disimpan ke sistem POS Me.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // Summary Stats Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    title: 'Berhasil Disimpan',
                    count: res.successCount,
                    subtitle: '${res.createdCount} Baru, ${res.updatedCount} Update',
                    color: Colors.green,
                    icon: Icons.check,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    title: 'Dilewati (Error)',
                    count: res.skippedCount,
                    subtitle: 'Baris data tidak valid',
                    color: Colors.orange,
                    icon: Icons.remove_circle_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    title: 'Gagal Eksekusi',
                    count: res.failedCount,
                    subtitle: 'Gagal tulis database',
                    color: Colors.red,
                    icon: Icons.cancel_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Details of Errors if any
            if (res.errorMessages.isNotEmpty) ...[
              Text(
                'CATATAN BARIS YANG DILEWATI / GAGAL',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Colors.red.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade200),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: res.errorMessages.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        res.errorMessages[index],
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Finish Button
            FilledButton.icon(
              onPressed: () => controller.finishWizard(),
              icon: const Icon(Icons.done_all),
              label: const Text('Selesai & Tutup Wizard'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildSummaryMetric(
    BuildContext context, {
    required String title,
    required int count,
    required String subtitle,
    required MaterialColor color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: color.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color.shade800, size: 28),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color.shade900,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color.shade900)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: color.shade700)),
          ],
        ),
      ),
    );
  }
}
