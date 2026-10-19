import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/models/import_models.dart';
import '../../../data/repositories/import_repository.dart';

class ImportWizardController extends GetxController {
  final ImportRepository _importRepo = Get.find<ImportRepository>();

  // Langkah Wizard: 0=Pilih Berkas, 1=Pemetaan Kolom, 2=Preview & Opsi, 3=Eksekusi, 4=Ringkasan
  final currentStep = 0.obs;

  // STEP 0: Pilih Jenis Data & File
  final selectedType = ImportTemplateType.product.obs;
  final selectedFilePath = ''.obs;
  final selectedFileName = ''.obs;
  final fileSizeFormatted = ''.obs;
  final isParsingFile = false.obs;

  List<String> fileHeaders = [];
  List<List<dynamic>> parsedFileRows = [];

  // STEP 1: Pemetaan Kolom
  final availableFileHeaders = <String>[].obs;
  final targetFields = <String, String>{}.obs;
  final columnMapping = <String, RxnString>{}.obs;

  // STEP 2: Preview & Validasi
  final isValidating = false.obs;
  final previewRows = <ImportPreviewRow>[].obs;
  final filterTab = 'semua'.obs; // 'semua', 'valid', 'error'
  final searchQuery = ''.obs;
  final options = const ImportOptions().obs;

  // STEP 3: Eksekusi & Progress
  final isExecuting = false.obs;
  final progressCurrent = 0.obs;
  final progressTotal = 0.obs;
  final progressMessage = ''.obs;

  // STEP 4: Ringkasan Hasil
  final summary = Rxn<ImportSummary>();

  @override
  void onInit() {
    super.onInit();
    _checkInitialAccess();

    if (Get.arguments is Map && Get.arguments['type'] is ImportTemplateType) {
      selectedType.value = Get.arguments['type'] as ImportTemplateType;
    }

    _initTargetFieldsForType(selectedType.value);
  }

  void _checkInitialAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        FeatureGate.to.requireFeature(Feature.importExport);
        return;
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.importManage)) {
        Get.snackbar(
          'Akses Ditolak',
          'Anda tidak memiliki izin untuk mengimpor data.',
          snackPosition: SnackPosition.BOTTOM,
        );
        Get.back();
      }
    }
  }

  void setImportType(ImportTemplateType type) {
    selectedType.value = type;
    _initTargetFieldsForType(type);
    // Reset file jika tipe diganti
    selectedFilePath.value = '';
    selectedFileName.value = '';
    fileHeaders = [];
    parsedFileRows = [];
  }

  void _initTargetFieldsForType(ImportTemplateType type) {
    targetFields.clear();
    columnMapping.clear();

    switch (type) {
      case ImportTemplateType.product:
        targetFields.addAll({
          'nama': 'Nama Produk *',
          'sku': 'Kode SKU',
          'barcode': 'Kode Barcode',
          'kategori': 'Kategori',
          'satuan': 'Satuan',
          'harga_beli': 'Harga Beli (Modal)',
          'harga_jual': 'Harga Jual *',
          'stok_awal': 'Stok Awal',
          'stok_minimum': 'Stok Minimum',
        });
        break;
      case ImportTemplateType.category:
        targetFields.addAll({
          'nama': 'Nama Kategori *',
        });
        break;
      case ImportTemplateType.supplier:
        targetFields.addAll({
          'nama': 'Nama Supplier *',
          'telepon': 'Nomor Telepon',
          'alamat': 'Alamat Usaha',
        });
        break;
    }

    for (final key in targetFields.keys) {
      columnMapping[key] = RxnString();
    }
  }

  // =========================================================================
  // LANGKAH 0: PILIH BERKAS
  // =========================================================================

  Future<void> pickFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (picked == null) return;

      final path = picked.path;
      if (path == null) {
        Get.snackbar('Kesalahan Berkas', 'Jalur berkas tidak dapat diakses.');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        Get.snackbar('Kesalahan Berkas', 'Berkas yang dipilih tidak ditemukan.');
        return;
      }

      final size = await file.length();
      fileSizeFormatted.value = _formatFileSize(size);
      selectedFilePath.value = path;
      selectedFileName.value = picked.name;

      await _parseFile(file, picked.name);
    } catch (e) {
      Get.snackbar('Gagal Membuka Berkas', 'Terjadi kesalahan: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _parseFile(File file, String name) async {
    isParsingFile.value = true;
    try {
      final ext = name.split('.').last.toLowerCase();
      List<List<dynamic>> rows = [];

      if (ext == 'csv') {
        final bytes = await file.readAsBytes();
        String text;
        try {
          text = utf8.decode(bytes);
        } catch (_) {
          text = latin1.decode(bytes);
        }
        text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        rows = csv.decode(text);
      } else if (ext == 'xlsx' || ext == 'xls') {
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        if (excel.tables.isEmpty) {
          throw const FormatException('Berkas Excel kosong atau tidak memiliki lembar kerja.');
        }
        final sheetName = excel.tables.keys.first;
        final sheet = excel.tables[sheetName]!;

        for (final row in sheet.rows) {
          final rowData = <dynamic>[];
          for (final cell in row) {
            rowData.add(_extractCellValue(cell));
          }
          rows.add(rowData);
        }
      }

      // Bersihkan baris yang sepenuhnya kosong
      final filteredRows = rows.where((r) => r.any((c) => c.toString().trim().isNotEmpty)).toList();

      if (filteredRows.isEmpty) {
        Get.snackbar('Berkas Kosong', 'Berkas tidak memuat baris data yang valid.');
        return;
      }

      // Baris pertama dianggap sebagai Header
      fileHeaders = filteredRows.first.map((c) => c.toString().trim()).toList();
      parsedFileRows = filteredRows.skip(1).toList();

      availableFileHeaders.assignAll(fileHeaders);

      // Auto-detect pencocokan kolom
      _autoDetectColumnMapping();

      // Pindah ke langkah 1 (Pemetaan Kolom)
      currentStep.value = 1;
    } catch (e) {
      Get.snackbar('Gagal Membaca Berkas', 'Terjadi kesalahan saat mengurai berkas: $e');
    } finally {
      isParsingFile.value = false;
    }
  }

  dynamic _extractCellValue(dynamic cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    try {
      final inner = (val as dynamic).value;
      if (inner != null) return inner;
    } catch (_) {}
    return val.toString();
  }

  // =========================================================================
  // LANGKAH 1: PEMETAAN KOLOM
  // =========================================================================

  void _autoDetectColumnMapping() {
    final synonyms = <String, List<String>>{
      'nama': ['nama', 'name', 'namaproduk', 'productname', 'namabarang', 'barang', 'judul'],
      'sku': ['sku', 'kode', 'kodesku', 'kodeproduk', 'kodebarang'],
      'barcode': ['barcode', 'kodebarcode', 'bar_code', 'upc', 'ean', 'kodebatang'],
      'kategori': ['kategori', 'category', 'kelompok', 'grup'],
      'satuan': ['satuan', 'unit', 'uom', 'sat'],
      'harga_beli': ['hargabeli', 'beli', 'cost', 'costprice', 'hpp', 'modal', 'hargamodal'],
      'harga_jual': ['hargajual', 'jual', 'price', 'sellprice', 'sellingprice', 'harga'],
      'stok_awal': ['stokawal', 'stok', 'stock', 'qty', 'jumlah', 'kuantitas', 'saldoawal'],
      'stok_minimum': ['stokminimum', 'minstok', 'minstock', 'minimum', 'stokmin'],
      'telepon': ['telepon', 'telp', 'phone', 'hp', 'notelp', 'nomortelepon', 'whatsapp', 'wa'],
      'alamat': ['alamat', 'address', 'lokasi'],
    };

    for (final targetKey in targetFields.keys) {
      final synList = synonyms[targetKey] ?? [targetKey];
      String? matchedHeader;

      for (final header in fileHeaders) {
        final cleanHeader = header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (synList.any((s) => cleanHeader == s || cleanHeader.contains(s))) {
          matchedHeader = header;
          break;
        }
      }

      if (matchedHeader != null) {
        columnMapping[targetKey]?.value = matchedHeader;
      }
    }
  }

  Future<void> confirmMappingAndProceedToPreview() async {
    // Validasi field wajib
    if (columnMapping['nama']?.value == null) {
      Get.snackbar('Pemetaan Wajib', 'Kolom "Nama" wajib dipetakan ke salah satu kolom berkas.');
      return;
    }

    if (selectedType.value == ImportTemplateType.product) {
      if (columnMapping['harga_jual']?.value == null) {
        Get.snackbar('Pemetaan Wajib', 'Kolom "Harga Jual" wajib dipetakan ke salah satu kolom berkas.');
        return;
      }
    }

    await revalidatePreviewData();
    currentStep.value = 2;
  }

  // =========================================================================
  // LANGKAH 2: PREVIEW & VALIDASI
  // =========================================================================

  Future<void> revalidatePreviewData() async {
    isValidating.value = true;
    try {
      // Bentuk daftar baris raw terpetakan
      final mappedRows = <Map<String, dynamic>>[];
      for (final row in parsedFileRows) {
        final rowMap = <String, dynamic>{};
        for (final entry in columnMapping.entries) {
          final targetKey = entry.key;
          final headerName = entry.value.value;
          if (headerName != null) {
            final colIndex = fileHeaders.indexOf(headerName);
            if (colIndex >= 0 && colIndex < row.length) {
              rowMap[targetKey] = row[colIndex];
            }
          }
        }
        mappedRows.add(rowMap);
      }

      List<ImportPreviewRow> validated = [];
      switch (selectedType.value) {
        case ImportTemplateType.product:
          validated = await _importRepo.validateProductRows(
            rows: mappedRows,
            options: options.value,
          );
          break;
        case ImportTemplateType.category:
          validated = await _importRepo.validateCategoryRows(
            rows: mappedRows,
            options: options.value,
          );
          break;
        case ImportTemplateType.supplier:
          validated = await _importRepo.validateSupplierRows(
            rows: mappedRows,
            options: options.value,
          );
          break;
      }

      previewRows.assignAll(validated);
    } catch (e) {
      Get.snackbar('Validasi Gagal', 'Terjadi kesalahan saat memvalidasi baris: $e');
    } finally {
      isValidating.value = false;
    }
  }

  // Getter data terfilter
  int get totalRowsCount => previewRows.length;
  int get validRowsCount => previewRows.where((r) => r.isValid).length;
  int get errorRowsCount => previewRows.where((r) => !r.isValid).length;

  List<ImportPreviewRow> get filteredPreviewRows {
    var list = previewRows.toList();

    if (filterTab.value == 'valid') {
      list = list.where((r) => r.isValid).toList();
    } else if (filterTab.value == 'error') {
      list = list.where((r) => !r.isValid).toList();
    }

    final query = searchQuery.value.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((r) {
        final name = (r.rawValues['nama'] ?? '').toString().toLowerCase();
        final barcode = (r.rawValues['barcode'] ?? '').toString().toLowerCase();
        final sku = (r.rawValues['sku'] ?? '').toString().toLowerCase();
        return name.contains(query) || barcode.contains(query) || sku.contains(query);
      }).toList();
    }

    return list;
  }

  void updateOptions(ImportOptions newOptions) {
    options.value = newOptions;
    revalidatePreviewData();
  }

  // =========================================================================
  // LANGKAH 3: EKSEKUSI IMPOR PER BATCH
  // =========================================================================

  Future<void> startImportExecution() async {
    if (validRowsCount == 0) {
      Get.snackbar('Tidak Ada Data Valid', 'Tidak ada data valid yang dapat diimpor.');
      return;
    }

    if (errorRowsCount > 0 && !options.value.skipErrorRows) {
      Get.snackbar(
        'Terdapat Baris Error',
        'Opsi batalkan jika ada error aktif. Harap perbaiki berkas atau ubah ke lewati baris error.',
      );
      return;
    }

    currentStep.value = 3;
    isExecuting.value = true;
    progressCurrent.value = 0;
    progressTotal.value = validRowsCount;
    progressMessage.value = 'Mempersiapkan transaksi impor massal...';

    try {
      ImportSummary result;

      switch (selectedType.value) {
        case ImportTemplateType.product:
          result = await _importRepo.executeImportProducts(
            previewRows: previewRows,
            options: options.value,
            fileName: selectedFileName.value,
            onProgress: (current, total, msg) {
              progressCurrent.value = current;
              progressTotal.value = total;
              progressMessage.value = msg;
            },
          );
          break;
        case ImportTemplateType.category:
          result = await _importRepo.executeImportCategories(
            previewRows: previewRows,
            options: options.value,
            fileName: selectedFileName.value,
            onProgress: (current, total, msg) {
              progressCurrent.value = current;
              progressTotal.value = total;
              progressMessage.value = msg;
            },
          );
          break;
        case ImportTemplateType.supplier:
          result = await _importRepo.executeImportSuppliers(
            previewRows: previewRows,
            options: options.value,
            fileName: selectedFileName.value,
            onProgress: (current, total, msg) {
              progressCurrent.value = current;
              progressTotal.value = total;
              progressMessage.value = msg;
            },
          );
          break;
      }

      summary.value = result;
      currentStep.value = 4;
    } catch (e) {
      Get.snackbar('Gagal Eksekusi Impor', 'Terjadi kesalahan: $e', snackPosition: SnackPosition.BOTTOM);
      currentStep.value = 2; // Kembali ke preview
    } finally {
      isExecuting.value = false;
    }
  }

  void finishWizard() {
    Get.back();
  }
}
