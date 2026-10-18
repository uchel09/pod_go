import 'package:get/get.dart';
import 'package:printing/printing.dart';

import '../../data/repositories/settings_repository.dart';
import '../services/audit_service.dart';
import '../services/pdf/receipt_pdf_service.dart';
import 'esc_pos_generator.dart';
import 'printers/esc_pos_receipt_printer.dart';
import 'printers/pdf_receipt_printer.dart';
import 'receipt_data.dart';
import 'receipt_mode.dart';
import 'receipt_printer.dart';
import 'transports/bluetooth_classic_transport.dart';
import 'transports/network_transport.dart';
import 'transports/windows_spooler_transport.dart';

/// Service singleton GetX untuk mengelola konfigurasi, transport, dan pencetakan struk
class PrinterManager extends GetxService {
  static PrinterManager get to => Get.find<PrinterManager>();

  final SettingsRepository _settingsRepo = Get.find<SettingsRepository>();

  // Konstanta Kunci Pengaturan di app_settings
  static const keyType = 'printer.type'; // 'bluetooth' | 'usb_windows' | 'lan' | 'pdf_only'
  static const keyTarget = 'printer.target'; // MAC address / Printer Name / IP
  static const keyPort = 'printer.port'; // Port LAN (default 9100)
  static const keyPaperWidth = 'printer.paper_width'; // '58' | '80'
  static const keyCharsPerLine = 'printer.chars_per_line'; // default 32 atau 48
  static const keyCutMode = 'printer.cut_mode'; // 'full' | 'partial' | 'none'
  static const keyFeedLines = 'printer.feed_lines'; // default 3
  static const keyReceiptMode = ReceiptMode.settingKey; // 'ask' | 'always' | 'never'
  static const keyCashDrawer = 'printer.cash_drawer'; // 'true' | 'false'
  static const keyDrawerPin = 'printer.drawer_pin'; // '0' | '1'
  static const keyCopies = 'printer.copies'; // default 1

  /// Kunci lama (Prompt 9B) sebelum digabung ke [keyReceiptMode]. Hanya dibaca
  /// sekali untuk migrasi: 'true' menjadi [ReceiptMode.always], selain itu [ReceiptMode.ask].
  static const _legacyKeyAutoPrint = 'printer.auto_print';

  // Reactive Settings Cache
  final printerType = 'pdf_only'.obs;
  final printerTarget = ''.obs;
  final printerPort = '9100'.obs;
  final paperWidth = '58'.obs;
  final charsPerLine = 32.obs;
  final cutMode = 'partial'.obs;
  final feedLines = 3.obs;
  final receiptMode = ReceiptMode.ask.obs;
  final cashDrawer = false.obs;
  final drawerPin = 0.obs;
  final copies = 1.obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  /// Memuat seluruh preferensi printer dari app_settings
  Future<void> loadSettings() async {
    printerType.value = await _settingsRepo.getSetting(keyType) ?? 'pdf_only';
    printerTarget.value = await _settingsRepo.getSetting(keyTarget) ?? '';
    printerPort.value = await _settingsRepo.getSetting(keyPort) ?? '9100';
    paperWidth.value = await _settingsRepo.getSetting(keyPaperWidth) ?? '58';

    final charsStr = await _settingsRepo.getSetting(keyCharsPerLine);
    charsPerLine.value = int.tryParse(charsStr ?? '') ?? (paperWidth.value == '80' ? 48 : 32);

    cutMode.value = await _settingsRepo.getSetting(keyCutMode) ?? 'partial';
    feedLines.value = int.tryParse(await _settingsRepo.getSetting(keyFeedLines) ?? '') ?? 3;
    receiptMode.value = await _loadReceiptMode();
    cashDrawer.value = (await _settingsRepo.getSetting(keyCashDrawer)) == 'true';
    drawerPin.value = int.tryParse(await _settingsRepo.getSetting(keyDrawerPin) ?? '') ?? 0;
    copies.value = int.tryParse(await _settingsRepo.getSetting(keyCopies) ?? '') ?? 1;
  }

  /// Membaca [ReceiptMode]; bila belum pernah disimpan, migrasikan dari opsi
  /// cetak otomatis lama agar tidak ada dua setelan yang saling bertentangan.
  Future<ReceiptMode> _loadReceiptMode() async {
    final stored = await _settingsRepo.getSetting(keyReceiptMode);
    if (stored != null) return ReceiptMode.parse(stored);

    final legacy = await _settingsRepo.getSetting(_legacyKeyAutoPrint);
    final migrated = legacy == 'true' ? ReceiptMode.always : ReceiptMode.ask;
    await _settingsRepo.setSetting(keyReceiptMode, migrated.key);
    return migrated;
  }

  /// Apakah printer hardware (Bluetooth/USB/LAN) saat ini terkonfigurasi
  bool get isHardwareConfigured =>
      printerType.value != 'pdf_only' && printerTarget.value.trim().isNotEmpty;

  /// Cetak otomatis hanya berlaku bila mode [ReceiptMode.always] DAN ada printer
  /// hardware. Tanpa printer hardware, mode "always" tidak membuka dialog cetak
  /// sistem di setiap transaksi.
  bool get shouldAutoPrint => receiptMode.value == ReceiptMode.always && isHardwareConfigured;

  CutMode get _parsedCutMode {
    switch (cutMode.value.toLowerCase()) {
      case 'full':
        return CutMode.full;
      case 'none':
        return CutMode.none;
      case 'partial':
      default:
        return CutMode.partial;
    }
  }

  /// Menghasilkan instance [ReceiptPrinter] berdasarkan konfigurasi saat ini.
  ///
  /// Pulse laci kasir TIDAK ikut dikirim bersama struk (laci dibuka terpisah saat
  /// pembayaran tunai lewat [openCashDrawer]), kecuali [pulseDrawerWithPrint] true
  /// (dipakai cetak uji coba).
  ReceiptPrinter getPrinter({bool forcePdf = false, bool pulseDrawerWithPrint = false}) {
    if (forcePdf || printerType.value == 'pdf_only') {
      return PdfReceiptPrinter(receiptWidth: paperWidth.value);
    }

    final target = printerTarget.value.trim();
    final generator = EscPosGenerator(charsPerLine: charsPerLine.value);

    switch (printerType.value) {
      case 'bluetooth':
        return EscPosReceiptPrinter(
          transport: BluetoothClassicTransport(macAddress: target),
          generator: generator,
          cutMode: _parsedCutMode,
          feedLines: feedLines.value,
          openDrawer: pulseDrawerWithPrint && cashDrawer.value,
          drawerPin: drawerPin.value,
          copies: copies.value,
        );

      case 'usb_windows':
        return EscPosReceiptPrinter(
          transport: WindowsSpoolerTransport(printerName: target),
          generator: generator,
          cutMode: _parsedCutMode,
          feedLines: feedLines.value,
          openDrawer: pulseDrawerWithPrint && cashDrawer.value,
          drawerPin: drawerPin.value,
          copies: copies.value,
        );

      case 'lan':
        final port = int.tryParse(printerPort.value) ?? 9100;
        return EscPosReceiptPrinter(
          transport: NetworkTransport(host: target, port: port),
          generator: generator,
          cutMode: _parsedCutMode,
          feedLines: feedLines.value,
          openDrawer: pulseDrawerWithPrint && cashDrawer.value,
          drawerPin: drawerPin.value,
          copies: copies.value,
        );

      default:
        return PdfReceiptPrinter(receiptWidth: paperWidth.value);
    }
  }

  /// Mencetak nota belanja dengan penanganan error dan audit logging
  Future<PrintResult> printReceipt(ReceiptData data, {bool forcePdf = false}) async {
    final printer = getPrinter(forcePdf: forcePdf);
    final result = await printer.printReceipt(data);

    if (!result.success && !forcePdf && printerType.value != 'pdf_only') {
      // Catat kegagalan cetak ke AuditService (tanpa data sensitif)
      _logPrinterFailure(
        action: 'print_receipt',
        error: result.error ?? 'Unknown print failure',
        invoiceNo: data.invoiceNo,
      );
    }

    return result;
  }

  /// Mencetak struk tes konfigurasi printer
  Future<PrintResult> printTest({bool forcePdf = false}) async {
    final printer = getPrinter(forcePdf: forcePdf, pulseDrawerWithPrint: true);
    final result = await printer.printTest();

    if (!result.success && !forcePdf && printerType.value != 'pdf_only') {
      _logPrinterFailure(
        action: 'test_print',
        error: result.error ?? 'Unknown test print failure',
      );
    }

    return result;
  }

  /// Membuat struk PDF lalu membagikan/menyimpannya lewat dialog sistem.
  /// Tidak menyentuh printer thermal sehingga tetap bisa dipakai saat printer mati.
  Future<PrintResult> savePdf(ReceiptData data) async {
    try {
      final bytes = await ReceiptPdfService.generateFromReceiptData(
        data,
        receiptWidth: paperWidth.value,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'struk_${data.invoiceNo}.pdf',
      );
      return const PrintResult(
        success: true,
        message: 'Struk PDF siap disimpan/dibagikan.',
        isFallbackPdf: true,
      );
    } catch (e) {
      return PrintResult.failure('Gagal membuat struk PDF: $e', isFallbackPdf: true);
    }
  }

  /// Mengirim sinyal pembukaan laci kasir secara langsung
  Future<void> openCashDrawer() async {
    if (!cashDrawer.value || printerType.value == 'pdf_only') return;
    try {
      final printer = getPrinter();
      await printer.openCashDrawer();
    } catch (e) {
      _logPrinterFailure(
        action: 'open_cash_drawer',
        error: e.toString(),
      );
    }
  }

  void _logPrinterFailure({
    required String action,
    required String error,
    String? invoiceNo,
  }) {
    if (Get.isRegistered<AuditService>()) {
      try {
        AuditService.to.log(
          action: 'printer.fail',
          entity: 'printer',
          detail: {
            'action': action,
            'printerType': printerType.value,
            'target': printerTarget.value,
            'invoiceNo': ?invoiceNo,
            'error': error,
          },
        );
      } catch (_) {}
    }
  }
}
