import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/printing/esc_pos_generator.dart';
import '../../../core/printing/printer_manager.dart';
import '../../../core/printing/receipt_mode.dart';
import '../../../core/printing/printers/esc_pos_receipt_printer.dart';
import '../../../core/printing/printers/pdf_receipt_printer.dart';
import '../../../core/printing/receipt_printer.dart';
import '../../../core/printing/transports/bluetooth_classic_transport.dart';
import '../../../core/printing/transports/network_transport.dart';
import '../../../core/printing/transports/windows_spooler_transport.dart';
import '../../../core/utils/app_exception.dart';
import '../../../data/repositories/settings_repository.dart';

class PrinterSettingsController extends GetxController {
  final SettingsRepository _settingsRepo = Get.find<SettingsRepository>();
  final PrinterManager _printerManager = PrinterManager.to;

  // Hak Akses
  bool get canManageSettings => PermissionService.to.can(PermissionKeys.settingsManage);

  // Form State
  final selectedType = 'pdf_only'.obs; // 'bluetooth' | 'usb_windows' | 'lan' | 'pdf_only'
  final selectedTarget = ''.obs; // MAC address / Printer Name / IP
  final lanIpController = TextEditingController();
  final lanPortController = TextEditingController(text: '9100');

  final paperWidth = '58'.obs; // '58' | '80'
  final charsPerLine = 32.obs;
  final cutMode = 'partial'.obs; // 'full' | 'partial' | 'none'
  final feedLines = 3.obs;
  final receiptMode = ReceiptMode.ask.obs;
  final cashDrawer = false.obs;
  final drawerPin = 0.obs; // 0 (Pin 2) | 1 (Pin 5)
  final copies = 1.obs;

  // List Devices
  final bluetoothDevices = <BluetoothInfo>[].obs;
  final windowsPrinters = <Printer>[].obs;

  final isLoadingDevices = false.obs;
  final isTestingConnection = false.obs;
  final isTestingPrint = false.obs;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get isWindows => !kIsWeb && Platform.isWindows;

  @override
  void onInit() {
    super.onInit();
    _loadFromManager();
    refreshDevices();
  }

  @override
  void onClose() {
    lanIpController.dispose();
    lanPortController.dispose();
    super.onClose();
  }

  void _loadFromManager() {
    selectedType.value = _printerManager.printerType.value;
    selectedTarget.value = _printerManager.printerTarget.value;
    paperWidth.value = _printerManager.paperWidth.value;
    charsPerLine.value = _printerManager.charsPerLine.value;
    cutMode.value = _printerManager.cutMode.value;
    feedLines.value = _printerManager.feedLines.value;
    receiptMode.value = _printerManager.receiptMode.value;
    cashDrawer.value = _printerManager.cashDrawer.value;
    drawerPin.value = _printerManager.drawerPin.value;
    copies.value = _printerManager.copies.value;

    if (selectedType.value == 'lan') {
      lanIpController.text = _printerManager.printerTarget.value;
      lanPortController.text = _printerManager.printerPort.value;
    }
  }

  /// Mengubah tipe printer dan menyesuaikan default chars per line
  void setPrinterType(String type) {
    selectedType.value = type;
    if (type == 'bluetooth' && bluetoothDevices.isEmpty) {
      refreshDevices();
    } else if (type == 'usb_windows' && windowsPrinters.isEmpty) {
      refreshDevices();
    }
  }

  void setPaperWidth(String width) {
    paperWidth.value = width;
    charsPerLine.value = width == '80' ? 48 : 32;
  }

  /// Memuat daftar printer dari sistem (Bluetooth di Android, Spooler di Windows)
  Future<void> refreshDevices() async {
    isLoadingDevices.value = true;
    try {
      if (isAndroid) {
        // Minta izin Bluetooth jika Android 12+
        if (await Permission.bluetoothConnect.isDenied) {
          await Permission.bluetoothConnect.request();
        }
        if (await Permission.bluetoothScan.isDenied) {
          await Permission.bluetoothScan.request();
        }

        final devices = await PrintBluetoothThermal.pairedBluetooths;
        bluetoothDevices.assignAll(devices);
      }

      if (isWindows) {
        final printers = await Printing.listPrinters();
        windowsPrinters.assignAll(printers);
      }
    } catch (e) {
      Get.snackbar('Perangkat', 'Gagal memindai perangkat: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingDevices.value = false;
    }
  }

  /// Menguji koneksi jaringan ke printer LAN port 9100
  Future<void> testLanConnection() async {
    final ip = lanIpController.text.trim();
    final port = int.tryParse(lanPortController.text.trim()) ?? 9100;

    if (ip.isEmpty) {
      Get.snackbar('Input Error', 'Alamat IP printer belum diisi.', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isTestingConnection.value = true;
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
      await socket.close();
      socket.destroy();
      Get.snackbar(
        'Koneksi Berhasil',
        'Printer LAN pada $ip:$port terhubung!',
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Koneksi Gagal',
        'Tidak dapat menghubungi $ip:$port ($e)',
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isTestingConnection.value = false;
    }
  }

  /// Menyimpan seluruh konfigurasi ke database app_settings
  Future<void> saveSettings() async {
    if (!canManageSettings) {
      throw const AppException('Akses ditolak: Anda tidak memiliki izin settings.manage.');
    }

    String target = selectedTarget.value.trim();
    String port = '9100';

    if (selectedType.value == 'lan') {
      target = lanIpController.text.trim();
      port = lanPortController.text.trim().isEmpty ? '9100' : lanPortController.text.trim();
    }

    await _settingsRepo.setSetting(PrinterManager.keyType, selectedType.value);
    await _settingsRepo.setSetting(PrinterManager.keyTarget, target);
    await _settingsRepo.setSetting(PrinterManager.keyPort, port);
    await _settingsRepo.setSetting(PrinterManager.keyPaperWidth, paperWidth.value);
    await _settingsRepo.setSetting(PrinterManager.keyCharsPerLine, charsPerLine.value.toString());
    await _settingsRepo.setSetting(PrinterManager.keyCutMode, cutMode.value);
    await _settingsRepo.setSetting(PrinterManager.keyFeedLines, feedLines.value.toString());
    await _settingsRepo.setSetting(PrinterManager.keyReceiptMode, receiptMode.value.key);
    await _settingsRepo.setSetting(PrinterManager.keyCashDrawer, cashDrawer.value ? 'true' : 'false');
    await _settingsRepo.setSetting(PrinterManager.keyDrawerPin, drawerPin.value.toString());
    await _settingsRepo.setSetting(PrinterManager.keyCopies, copies.value.toString());

    // Muat ulang cache di PrinterManager
    await _printerManager.loadSettings();

    Get.snackbar(
      'Pengaturan Disimpan',
      'Konfigurasi printer berhasil disimpan.',
      backgroundColor: Colors.green.shade700,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Menjalankan cetak uji coba sesuai pengaturan yang sedang aktif pada form
  Future<void> runTestPrint() async {
    isTestingPrint.value = true;
    try {
      ReceiptPrinter printer;

      if (selectedType.value == 'pdf_only') {
        printer = PdfReceiptPrinter(receiptWidth: paperWidth.value);
      } else {
        final generator = EscPosGenerator(charsPerLine: charsPerLine.value);
        CutMode parsedCut = CutMode.partial;
        if (cutMode.value == 'full') parsedCut = CutMode.full;
        if (cutMode.value == 'none') parsedCut = CutMode.none;

        if (selectedType.value == 'bluetooth') {
          final mac = selectedTarget.value.trim();
          if (mac.isEmpty) {
            throw const AppException('Pilih perangkat printer Bluetooth terlebih dahulu.');
          }
          printer = EscPosReceiptPrinter(
            transport: BluetoothClassicTransport(macAddress: mac),
            generator: generator,
            cutMode: parsedCut,
            feedLines: feedLines.value,
            openDrawer: cashDrawer.value,
            drawerPin: drawerPin.value,
            copies: copies.value,
          );
        } else if (selectedType.value == 'usb_windows') {
          final pName = selectedTarget.value.trim();
          if (pName.isEmpty) {
            throw const AppException('Pilih nama printer Windows terlebih dahulu.');
          }
          printer = EscPosReceiptPrinter(
            transport: WindowsSpoolerTransport(printerName: pName),
            generator: generator,
            cutMode: parsedCut,
            feedLines: feedLines.value,
            openDrawer: cashDrawer.value,
            drawerPin: drawerPin.value,
            copies: copies.value,
          );
        } else if (selectedType.value == 'lan') {
          final ip = lanIpController.text.trim();
          final port = int.tryParse(lanPortController.text.trim()) ?? 9100;
          if (ip.isEmpty) {
            throw const AppException('Masukkan alamat IP printer LAN.');
          }
          printer = EscPosReceiptPrinter(
            transport: NetworkTransport(host: ip, port: port),
            generator: generator,
            cutMode: parsedCut,
            feedLines: feedLines.value,
            openDrawer: cashDrawer.value,
            drawerPin: drawerPin.value,
            copies: copies.value,
          );
        } else {
          printer = PdfReceiptPrinter(receiptWidth: paperWidth.value);
        }
      }

      final res = await printer.printTest();
      if (res.success) {
        Get.snackbar(
          'Tes Cetak Berhasil',
          res.message ?? 'Struk tes berhasil dikirim ke printer.',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          'Tes Cetak Gagal',
          res.error ?? 'Terjadi kesalahan saat mencetak.',
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } on AppException catch (e) {
      e.showSnackbar();
    } catch (e) {
      Get.snackbar('Error', 'Gagal tes cetak: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isTestingPrint.value = false;
    }
  }

  /// Menguji pembukaan laci kasir secara langsung
  Future<void> testCashDrawer() async {
    try {
      await _printerManager.openCashDrawer();
      Get.snackbar(
        'Laci Kasir',
        'Sinyal pulse laci kasir (Pin ${drawerPin.value}) telah dikirim.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Error', 'Gagal membuka laci kasir: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}
