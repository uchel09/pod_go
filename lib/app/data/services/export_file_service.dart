import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Layanan penyimpanan dan pembagian berkas hasil ekspor (Windows & Android).
class ExportFileService {
  ExportFileService._();

  /// Menyimpan byte berkas ke disk lokal.
  /// Di Windows/Android: mencoba membuka dialog simpan berkas asli (`FilePicker.saveFile`),
  /// dan jika batal/tidak didukung, secara otomatis menyimpan ke folder Downloads/Documents.
  static Future<String?> saveFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    final uint8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Simpan Berkas Ekspor: $fileName',
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

    // Fallback: simpan ke folder Downloads atau Dokumen Aplikasi
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();

    final outputPath = '${dir.path}${Platform.pathSeparator}$fileName';
    final file = File(outputPath);
    await file.writeAsBytes(uint8, flush: true);
    return outputPath;
  }

  /// Membuka lembar pembagian sistem (Share Sheet) di Android / mobile
  /// menggunakan paket resmi `share_plus`.
  static Future<void> shareFile(String filePath, {String? subject, String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
        subject: subject,
        text: text,
      ),
    );
  }

  /// Membuka lokasi file di sistem operasi (File Explorer di Windows, atau Share di Android).
  static Future<void> openOrShareFile(String filePath, {String? subject}) async {
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,', filePath]);
        return;
      } catch (_) {}
    }

    // Android / platform lain
    await shareFile(filePath, subject: subject);
  }
}

