import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../printer_transport.dart';
import '../../utils/app_exception.dart';

/// Transport untuk printer sistem Windows via Print Spooler (RAW datatype)
class WindowsSpoolerTransport implements PrinterTransport {
  final String printerName;
  bool _isConnected = false;

  WindowsSpoolerTransport({required this.printerName});

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (kIsWeb || !Platform.isWindows) {
      throw const AppException('Windows Spooler hanya didukung di sistem operasi Windows.');
    }

    if (printerName.trim().isEmpty) {
      throw const AppException('Nama printer Windows belum dipilih.');
    }

    try {
      using((arena) {
        final phPrinter = arena<ffi.Pointer>();
        final pName = PCWSTR(printerName.trim().toNativeUtf16(allocator: arena));

        final result = OpenPrinter(pName, phPrinter, ffi.nullptr);
        if (!result.value) {
          _isConnected = false;
          throw AppException(
            'Gagal membuka printer Windows "$printerName". '
            'Pastikan printer terpasang di sistem dan nama sesuai.',
          );
        }

        final hPrinter = PRINTER_HANDLE(phPrinter.value);
        ClosePrinter(hPrinter);
        _isConnected = true;
      });
    } catch (e) {
      _isConnected = false;
      if (e is AppException) rethrow;
      throw AppException('Terjadi kesalahan saat memeriksa printer Windows: $e');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (kIsWeb || !Platform.isWindows) {
      throw const AppException('Windows Spooler hanya didukung di sistem operasi Windows.');
    }

    if (printerName.trim().isEmpty) {
      throw const AppException('Nama printer Windows belum dipilih.');
    }

    try {
      using((arena) {
        final phPrinter = arena<ffi.Pointer>();
        final pName = PCWSTR(printerName.trim().toNativeUtf16(allocator: arena));

        // 1. Buka printer
        final openResult = OpenPrinter(pName, phPrinter, ffi.nullptr);
        if (!openResult.value) {
          _isConnected = false;
          final err = GetLastError();
          throw AppException('Gagal membuka printer "$printerName" (Win32 Error: $err).');
        }

        final hPrinter = PRINTER_HANDLE(phPrinter.value);

        try {
          // 2. Siapkan DOC_INFO_1 dengan format RAW (melewatkan perintah ESC/POS langsung ke printer)
          final docInfo = arena<DOC_INFO_1>()
            ..ref.pDocName = 'POS Me Receipt'.toPwstr(allocator: arena)
            ..ref.pOutputFile = PWSTR(ffi.nullptr)
            ..ref.pDatatype = 'RAW'.toPwstr(allocator: arena);

          // 3. Mulai Document
          final jobId = StartDocPrinter(hPrinter, 1, docInfo);
          if (jobId == 0) {
            final err = GetLastError();
            throw AppException('Gagal memulai dokumen cetak (StartDocPrinter Error: $err).');
          }

          try {
            // 4. Mulai Page
            if (!StartPagePrinter(hPrinter)) {
              final err = GetLastError();
              throw AppException('Gagal memulai halaman cetak (StartPagePrinter Error: $err).');
            }

            // 5. Salin bytes ke buffer native memory
            final pBytes = arena<ffi.Uint8>(bytes.length);
            pBytes.asTypedList(bytes.length).setAll(0, bytes);

            final pWritten = arena<ffi.Uint32>();

            // 6. Tulis raw bytes ke spooler
            final writeSuccess = WritePrinter(
              hPrinter,
              pBytes.cast(),
              bytes.length,
              pWritten,
            );

            if (!writeSuccess || pWritten.value != bytes.length) {
              final err = GetLastError();
              throw AppException('Gagal menulis data ke printer (WritePrinter Error: $err).');
            }
          } finally {
            EndPagePrinter(hPrinter);
            EndDocPrinter(hPrinter);
          }
        } finally {
          ClosePrinter(hPrinter);
        }
      });

      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      if (e is AppException) rethrow;
      throw AppException('Gagal mengirim data cetak ke spooler Windows: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }
}

