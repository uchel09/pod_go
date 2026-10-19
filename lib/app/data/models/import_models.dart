export '../services/import_template_service.dart' show ImportTemplateType;

/// Mode impor: Tambah baru saja (insert only) atau Perbarui jika barcode/SKU sudah ada (upsert)
enum ImportMode {
  upsert,
  insertOnly;

  String get displayName {
    switch (this) {
      case ImportMode.upsert:
        return 'Perbarui data jika Barcode/SKU sudah ada (Upsert)';
      case ImportMode.insertOnly:
        return 'Hanya tambah data baru (Tolak jika sudah ada)';
    }
  }
}

/// Opsi dan konfigurasi pelaksanaan impor
class ImportOptions {
  final ImportMode mode;
  final bool autoCreateCategory;
  final bool autoCreateUnit;
  final bool correctStock;
  final bool skipErrorRows;

  const ImportOptions({
    this.mode = ImportMode.upsert,
    this.autoCreateCategory = true,
    this.autoCreateUnit = true,
    this.correctStock = false,
    this.skipErrorRows = true,
  });

  ImportOptions copyWith({
    ImportMode? mode,
    bool? autoCreateCategory,
    bool? autoCreateUnit,
    bool? correctStock,
    bool? skipErrorRows,
  }) {
    return ImportOptions(
      mode: mode ?? this.mode,
      autoCreateCategory: autoCreateCategory ?? this.autoCreateCategory,
      autoCreateUnit: autoCreateUnit ?? this.autoCreateUnit,
      correctStock: correctStock ?? this.correctStock,
      skipErrorRows: skipErrorRows ?? this.skipErrorRows,
    );
  }
}

/// Representasi data satu baris pada tahapan Preview impor
class ImportPreviewRow {
  final int rowIndex; // Urutan data (1, 2, 3...)
  final int fileLineNumber; // Nomor baris fisik di file (biasanya rowIndex + 1 jika ada header)
  final Map<String, dynamic> rawValues;
  final Map<String, dynamic> parsedValues;
  final bool isValid;
  final bool isUpdate;
  final int? existingEntityId;
  final List<String> errors;
  final List<String> warnings;

  const ImportPreviewRow({
    required this.rowIndex,
    required this.fileLineNumber,
    required this.rawValues,
    required this.parsedValues,
    required this.isValid,
    this.isUpdate = false,
    this.existingEntityId,
    this.errors = const [],
    this.warnings = const [],
  });

  String? get errorSummary => errors.isNotEmpty ? errors.join('; ') : null;
}

/// Hasil akhir eksekusi impor
class ImportSummary {
  final int totalRows;
  final int successCount;
  final int createdCount;
  final int updatedCount;
  final int skippedCount;
  final int failedCount;
  final List<String> errorMessages;

  const ImportSummary({
    required this.totalRows,
    required this.successCount,
    this.createdCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
    this.errorMessages = const [],
  });
}

