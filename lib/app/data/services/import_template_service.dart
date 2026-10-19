import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

enum ImportTemplateType {
  product,
  category,
  supplier;

  String get displayName {
    switch (this) {
      case ImportTemplateType.product:
        return 'Produk';
      case ImportTemplateType.category:
        return 'Kategori';
      case ImportTemplateType.supplier:
        return 'Supplier';
    }
  }

  String get fileNamePrefix {
    switch (this) {
      case ImportTemplateType.product:
        return 'template_produk';
      case ImportTemplateType.category:
        return 'template_kategori';
      case ImportTemplateType.supplier:
        return 'template_supplier';
    }
  }
}

class ImportTemplateService {
  ImportTemplateService._();

  static const List<String> productHeaders = [
    'nama',
    'sku',
    'barcode',
    'kategori',
    'satuan',
    'harga_beli',
    'harga_jual',
    'stok_awal',
    'stok_minimum',
  ];

  static const List<List<dynamic>> productSampleRows = [
    [
      'Kopi Susu Gula Aren',
      'KOP-001',
      '8991234567890',
      'Minuman',
      'cup',
      8000,
      15000,
      50,
      10,
    ],
    [
      'Roti Bakar Coklat',
      'ROT-002',
      '',
      'Makanan',
      'porsi',
      10000,
      18000,
      20,
      5,
    ],
    [
      'Air Mineral 600ml',
      'AIR-003',
      '8999999111222',
      'Minuman',
      'botol',
      2500,
      5000,
      100,
      24,
    ],
  ];

  static const List<String> categoryHeaders = ['nama'];

  static const List<List<dynamic>> categorySampleRows = [
    ['Makanan'],
    ['Minuman'],
    ['Snack & Makanan Ringan'],
    ['Sembako'],
  ];

  static const List<String> supplierHeaders = ['nama', 'telepon', 'alamat'];

  static const List<List<dynamic>> supplierSampleRows = [
    [
      'PT Sumber Pangan Nusantara',
      '081234567890',
      'Jl. Industri Raya No. 10, Jakarta Barat',
    ],
    [
      'CV Berkah Jaya Abadi',
      '085678901234',
      'Jl. Pasar Baru No. 5, Surabaya',
    ],
  ];

  static List<String> getHeaders(ImportTemplateType type) {
    switch (type) {
      case ImportTemplateType.product:
        return productHeaders;
      case ImportTemplateType.category:
        return categoryHeaders;
      case ImportTemplateType.supplier:
        return supplierHeaders;
    }
  }

  static List<List<dynamic>> getSampleRows(ImportTemplateType type) {
    switch (type) {
      case ImportTemplateType.product:
        return productSampleRows;
      case ImportTemplateType.category:
        return categorySampleRows;
      case ImportTemplateType.supplier:
        return supplierSampleRows;
    }
  }

  /// Menghasilkan format string CSV baku dengan baris contoh
  static String generateCsv(ImportTemplateType type) {
    final headers = getHeaders(type);
    final rows = getSampleRows(type);
    final allRows = [headers, ...rows];
    return csv.encode(allRows);
  }

  /// Menghasilkan byte berkas Excel (.xlsx) dengan header dan baris contoh
  static List<int> generateXlsx(ImportTemplateType type) {
    final excel = Excel.createExcel();
    final sheetName = type.displayName;
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // Hapus sheet default bawaan library jika ada
    if (sheetName != 'Sheet1' && excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = getHeaders(type);
    final rows = getSampleRows(type);

    // Tulis header
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Tulis baris contoh
    for (final row in rows) {
      final cellValues = row.map<CellValue>((v) {
        if (v is int) return IntCellValue(v);
        if (v is double) return DoubleCellValue(v);
        return TextCellValue(v?.toString() ?? '');
      }).toList();
      sheet.appendRow(cellValues);
    }

    final bytes = excel.save();
    return bytes ?? <int>[];
  }

  /// Menyimpan file template ke disk lokal (Windows & Android)
  static Future<String?> saveTemplateFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    final uint8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Simpan Berkas Template: $fileName',
        fileName: fileName,
        bytes: uint8,
      );
      if (uri != null) {
        if (uri.hasScheme && uri.scheme == 'file') {
          return uri.toFilePath();
        }
        return uri.path;
      }
    } catch (_) {}

    // Fallback jika dialog dibatalkan atau platform tidak mendukung saveFile langsung
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final outputPath = '${dir.path}/$fileName';
    final file = File(outputPath);
    await file.writeAsBytes(uint8, flush: true);
    return outputPath;
  }
}
