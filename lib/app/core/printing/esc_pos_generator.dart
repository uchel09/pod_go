import 'dart:convert';
import 'receipt_data.dart';

enum EscPosAlign { left, center, right }

enum CutMode { full, partial, none }

/// Generator perintah ESC/POS murni dalam Dart.
/// Kompatibel dengan semua printer thermal standar (58 mm / 80 mm).
class EscPosGenerator {
  final int charsPerLine;

  const EscPosGenerator({this.charsPerLine = 32});

  // --- Konstanta Perintah ESC/POS ---
  static const List<int> cmdInit = [0x1B, 0x40]; // ESC @
  static const List<int> cmdBoldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> cmdBoldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> cmdDoubleSize = [0x1D, 0x21, 0x11]; // GS ! 0x11 (2x lebar & tinggi)
  static const List<int> cmdDoubleHeight = [0x1D, 0x21, 0x01]; // GS ! 0x01 (2x tinggi)
  static const List<int> cmdDoubleWidth = [0x1D, 0x21, 0x10]; // GS ! 0x10 (2x lebar)
  static const List<int> cmdNormalSize = [0x1D, 0x21, 0x00]; // GS ! 0x00 (normal)
  static const List<int> cmdAlignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> cmdAlignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> cmdAlignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  static const List<int> cmdCutFull = [0x1D, 0x56, 0x00]; // GS V 0
  static const List<int> cmdCutPartial = [0x1D, 0x56, 0x01]; // GS V 1

  /// Pulse buka laci kasir (ESC p m t1 t2)
  /// pin 0 = Pin 2 RJ11 (m=0)
  /// pin 1 = Pin 5 RJ11 (m=1)
  static List<int> cmdOpenDrawer({int pin = 0}) {
    final m = (pin == 1) ? 0x01 : 0x00;
    return [0x1B, 0x70, m, 0x19, 0xFA];
  }

  /// Feed baris (ESC d n)
  static List<int> cmdFeed(int lines) {
    final n = lines.clamp(1, 255);
    return [0x1B, 0x64, n];
  }

  // --- Sanitasi Karakter ke ASCII Aman ---

  /// Membersihkan teks agar hanya berisi karakter ASCII yang aman dicetak (32-126 dan \n).
  /// Mencegah printer mencetak simbol aneh / karakter rusak dari input UTF-8.
  static String sanitizeAscii(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code == 10) {
        // newline \n
        buffer.write('\n');
      } else if (code >= 32 && code <= 126) {
        buffer.writeCharCode(code);
      } else {
        // Konversi beberapa karakter umum ke ASCII yang setara
        switch (input[i]) {
          case '•':
          case '·':
            buffer.write('-');
            break;
          case '“':
          case '”':
            buffer.write('"');
            break;
          case '‘':
          case '’':
            buffer.write("'");
            break;
          case '–':
          case '—':
            buffer.write('-');
            break;
          case 'é':
          case 'è':
          case 'ê':
            buffer.write('e');
            break;
          case 'É':
          case 'È':
            buffer.write('E');
            break;
          case 'á':
          case 'à':
            buffer.write('a');
            break;
          case 'ó':
          case 'ò':
            buffer.write('o');
            break;
          case 'ú':
          case 'ù':
            buffer.write('u');
            break;
          default:
            buffer.write(' ');
            break;
        }
      }
    }
    return buffer.toString();
  }

  /// Membungkus teks panjang menjadi baris-baris sesuai batas lebar karakter
  static List<String> wordWrap(String text, int maxWidth) {
    final clean = sanitizeAscii(text).trim();
    if (clean.length <= maxWidth) return [clean];

    final lines = <String>[];
    final words = clean.split(' ');
    var currentLine = StringBuffer();

    for (final word in words) {
      if (word.length > maxWidth) {
        // Kata sangat panjang: potong paksa per maxWidth
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.toString());
          currentLine = StringBuffer();
        }
        var remaining = word;
        while (remaining.length > maxWidth) {
          lines.add(remaining.substring(0, maxWidth));
          remaining = remaining.substring(maxWidth);
        }
        currentLine.write(remaining);
      } else if (currentLine.length + (currentLine.isEmpty ? 0 : 1) + word.length <= maxWidth) {
        if (currentLine.isNotEmpty) currentLine.write(' ');
        currentLine.write(word);
      } else {
        lines.add(currentLine.toString());
        currentLine = StringBuffer(word);
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine.toString());
    }

    return lines;
  }

  /// Membuat baris dua kolom (kolom kiri rata kiri, kolom kanan rata kanan)
  static String formatRow2(String left, String right, int totalWidth) {
    final cleanLeft = sanitizeAscii(left);
    final cleanRight = sanitizeAscii(right);

    final availableSpaces = totalWidth - cleanLeft.length - cleanRight.length;
    if (availableSpaces >= 0) {
      return cleanLeft + (' ' * availableSpaces) + cleanRight;
    }

    // Jika teks kiri terlalu panjang, bungkus kiri dan letakkan kanan di baris terakhir
    final maxLeftWidth = (totalWidth - cleanRight.length - 1).clamp(0, totalWidth);
    final truncatedLeft = cleanLeft.substring(0, maxLeftWidth);
    final padding = totalWidth - truncatedLeft.length - cleanRight.length;
    return truncatedLeft + (' ' * (padding > 0 ? padding : 1)) + cleanRight;
  }

  /// Menghasilkan baris pemisah horizontal
  static String formatDivider(int width, [String char = '-']) {
    return char * width;
  }

  /// Menghasilkan byte cetak untuk seluruh nota [ReceiptData]
  List<int> generateReceipt(
    ReceiptData data, {
    CutMode cutMode = CutMode.partial,
    int feedLines = 3,
    bool openDrawer = false,
    int drawerPin = 0,
  }) {
    final bytes = <int>[];

    // 1. Inisialisasi printer
    bytes.addAll(cmdInit);

    // 2. Buka laci kasir jika dikonfigurasi aktif
    if (openDrawer) {
      bytes.addAll(cmdOpenDrawer(pin: drawerPin));
    }

    // 3. Header Toko (Center)
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(cmdBoldOn);
    bytes.addAll(cmdDoubleHeight);
    bytes.addAll(_encodeLine(data.storeName));
    bytes.addAll(cmdNormalSize);
    bytes.addAll(cmdBoldOff);

    if (data.storeAddress != null && data.storeAddress!.trim().isNotEmpty) {
      for (final line in wordWrap(data.storeAddress!, charsPerLine)) {
        bytes.addAll(_encodeLine(line));
      }
    }
    if (data.storePhone != null && data.storePhone!.trim().isNotEmpty) {
      bytes.addAll(_encodeLine('Telp: ${data.storePhone!}'));
    }

    if (data.isReturn) {
      bytes.addAll(cmdAlignCenter);
      bytes.addAll(cmdBoldOn);
      bytes.addAll(_encodeLine('*** BUKTI RETUR PENJUALAN ***'));
      bytes.addAll(cmdBoldOff);
    } else if (data.isReprint) {
      bytes.addAll(cmdAlignCenter);
      bytes.addAll(cmdBoldOn);
      bytes.addAll(_encodeLine('*** SALINAN ***'));
      bytes.addAll(cmdBoldOff);
    }

    // Garis Pemisah
    bytes.addAll(cmdAlignLeft);
    bytes.addAll(_encodeLine(formatDivider(charsPerLine)));

    // 4. Informasi Transaksi
    if (data.isReturn) {
      bytes.addAll(_encodeLine(formatRow2('No. Retur', data.returnNo ?? data.invoiceNo, charsPerLine)));
      if (data.originInvoiceNo != null) {
        bytes.addAll(_encodeLine(formatRow2('Nota Asal', data.originInvoiceNo!, charsPerLine)));
      }
    } else {
      bytes.addAll(_encodeLine(formatRow2('No. Nota', data.invoiceNo, charsPerLine)));
    }
    bytes.addAll(_encodeLine(formatRow2('Kasir', data.cashierName, charsPerLine)));
    final dateStr = '${_twoDigits(data.dateTime.day)}/${_twoDigits(data.dateTime.month)}/${data.dateTime.year} '
        '${_twoDigits(data.dateTime.hour)}:${_twoDigits(data.dateTime.minute)}';
    bytes.addAll(_encodeLine(formatRow2('Waktu', dateStr, charsPerLine)));

    // Garis Pemisah
    bytes.addAll(_encodeLine(formatDivider(charsPerLine)));

    // 5. Daftar Item
    for (final item in data.items) {
      // Baris nama barang (word-wrapped jika panjang)
      final nameLines = wordWrap(item.name, charsPerLine);
      for (final nLine in nameLines) {
        bytes.addAll(_encodeLine(nLine));
      }

      // Baris Qty x Harga dan Subtotal
      final qtyPriceStr = '  ${item.qty} x ${_formatNumber(item.price)}';
      final subtotalStr = _formatNumber(item.subtotal);
      bytes.addAll(_encodeLine(formatRow2(qtyPriceStr, subtotalStr, charsPerLine)));

      // Keterangan kondisi barang jika retur
      if (data.isReturn && !item.restock) {
        bytes.addAll(_encodeLine('    (Barang Rusak - Tidak Restock)'));
      }

      // Baris Diskon Item jika ada
      if (item.discount > 0) {
        final discStr = '-${_formatNumber(item.discount * item.qty)}';
        bytes.addAll(_encodeLine(formatRow2('    (Diskon)', discStr, charsPerLine)));
      }
    }

    // Garis Pemisah Rincian
    bytes.addAll(_encodeLine(formatDivider(charsPerLine)));

    // 6. Ringkasan Total
    final subtotalLabel = data.isReturn ? 'Subtotal Retur' : 'Subtotal';
    bytes.addAll(_encodeLine(formatRow2(subtotalLabel, _formatNumber(data.subtotal), charsPerLine)));

    final totalItemsDiscount = data.items.fold<int>(0, (sum, i) => sum + (i.discount * i.qty));
    final overallDiscount = (data.discount - totalItemsDiscount).clamp(0, data.discount);

    if (overallDiscount > 0) {
      bytes.addAll(_encodeLine(formatRow2('Diskon Nota', '-${_formatNumber(overallDiscount)}', charsPerLine)));
    }

    if (data.tax > 0) {
      final rateStr = data.taxRatePercentString.isNotEmpty ? ' (${data.taxRatePercentString})' : '';
      final taxLabel = data.isReturn
          ? 'Pajak Dikembalikan'
          : '${data.taxName ?? 'PPN'}$rateStr';
      bytes.addAll(_encodeLine(formatRow2(taxLabel, _formatNumber(data.tax), charsPerLine)));
    }

    // Total Belanja / Refund (Tebal)
    bytes.addAll(cmdBoldOn);
    final totalLabel = data.isReturn ? 'TOTAL REFUND' : 'TOTAL';
    bytes.addAll(_encodeLine(formatRow2(totalLabel, _formatNumber(data.total), charsPerLine)));
    bytes.addAll(cmdBoldOff);

    if (data.isReturn && data.returnReason != null && data.returnReason!.isNotEmpty) {
      bytes.addAll(_encodeLine(formatRow2('Alasan', data.returnReason!, charsPerLine)));
    }

    if (data.tax > 0 && data.taxMode == 'inclusive' && !data.isReturn) {
      final rateStr = data.taxRatePercentString.isNotEmpty ? ' ${data.taxRatePercentString}' : '';
      final incNote = '(Termasuk ${data.taxName ?? 'PPN'}$rateStr)';
      bytes.addAll(_encodeLine(formatRow2('', incNote, charsPerLine)));
    }

    // Garis Pemisah Pembayaran
    bytes.addAll(_encodeLine(formatDivider(charsPerLine, '-')));

    // 7. Rincian Pembayaran
    for (final p in data.payments) {
      final methodLabel = _formatPaymentMethod(p.method);
      bytes.addAll(_encodeLine(formatRow2(methodLabel, _formatNumber(p.amount), charsPerLine)));
    }

    bytes.addAll(_encodeLine(formatRow2('Kembalian', _formatNumber(data.change), charsPerLine)));

    // Garis Pemisah Footer
    bytes.addAll(_encodeLine(formatDivider(charsPerLine)));

    // 8. Catatan Kaki (Footer)
    bytes.addAll(cmdAlignCenter);
    if (data.footerNotes != null && data.footerNotes!.trim().isNotEmpty) {
      for (final line in wordWrap(data.footerNotes!, charsPerLine)) {
        bytes.addAll(_encodeLine(line));
      }
    } else {
      bytes.addAll(_encodeLine('Terima kasih atas kunjungan Anda!'));
      bytes.addAll(_encodeLine('Barang yang dibeli tidak dapat ditukar'));
    }

    // 9. Feed & Cut
    bytes.addAll(cmdFeed(feedLines));
    if (cutMode == CutMode.full) {
      bytes.addAll(cmdCutFull);
    } else if (cutMode == CutMode.partial) {
      bytes.addAll(cmdCutPartial);
    }

    return bytes;
  }

  /// Menghasilkan byte tes cetak untuk memastikan lebar karakter dan printer berfungsi
  List<int> generateTestPrint({
    CutMode cutMode = CutMode.partial,
    int feedLines = 3,
    bool openDrawer = false,
    int drawerPin = 0,
  }) {
    final bytes = <int>[];

    bytes.addAll(cmdInit);

    if (openDrawer) {
      bytes.addAll(cmdOpenDrawer(pin: drawerPin));
    }

    // Header Tes
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(cmdBoldOn);
    bytes.addAll(cmdDoubleHeight);
    bytes.addAll(_encodeLine('*** TES PRINTER POS ***'));
    bytes.addAll(cmdNormalSize);
    bytes.addAll(cmdBoldOff);
    bytes.addAll(_encodeLine('Koneksi & Perintah ESC/POS'));
    bytes.addAll(_encodeLine('Lebar Karakter: $charsPerLine Kolom'));
    bytes.addAll(cmdAlignLeft);

    bytes.addAll(_encodeLine(formatDivider(charsPerLine, '=')));

    // Garis Penggaris Karakter (Ruler)
    final ruler1 = List.generate(charsPerLine, (i) => ((i + 1) % 10).toString()).join();
    bytes.addAll(_encodeLine('PENGGARIS LEBAR:'));
    bytes.addAll(_encodeLine(ruler1));

    bytes.addAll(_encodeLine(formatDivider(charsPerLine, '-')));

    // Tes Perataan Teks
    bytes.addAll(cmdAlignLeft);
    bytes.addAll(_encodeLine('[Rata Kiri]'));
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(_encodeLine('[Rata Tengah]'));
    bytes.addAll(cmdAlignRight);
    bytes.addAll(_encodeLine('[Rata Kanan]'));
    bytes.addAll(cmdAlignLeft);

    bytes.addAll(_encodeLine(formatDivider(charsPerLine, '-')));

    // Tes Tebal & Ukuran
    bytes.addAll(cmdBoldOn);
    bytes.addAll(_encodeLine('Teks Huruf Tebal (Bold On)'));
    bytes.addAll(cmdBoldOff);
    bytes.addAll(_encodeLine('Teks Standar (Normal)'));

    // Tes Kolom Rata Kiri & Kanan
    bytes.addAll(_encodeLine(formatRow2('Kopi Susu Aren', '15.000', charsPerLine)));
    bytes.addAll(_encodeLine(formatRow2('Roti Bakar Cokelat', '12.000', charsPerLine)));
    bytes.addAll(cmdBoldOn);
    bytes.addAll(_encodeLine(formatRow2('TOTAL UJI COBA', '27.000', charsPerLine)));
    bytes.addAll(cmdBoldOff);

    bytes.addAll(_encodeLine(formatDivider(charsPerLine, '=')));

    // Status Fitur
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(_encodeLine('Laci Kasir: ${openDrawer ? 'Aktif (Pin $drawerPin)' : 'Nonaktif'}'));
    bytes.addAll(_encodeLine('Potong Kertas: ${cutMode.name.toUpperCase()}'));
    bytes.addAll(_encodeLine('Status: SIAP DIGUNAKAN'));

    // Feed & Cut
    bytes.addAll(cmdFeed(feedLines));
    if (cutMode == CutMode.full) {
      bytes.addAll(cmdCutFull);
    } else if (cutMode == CutMode.partial) {
      bytes.addAll(cmdCutPartial);
    }

    return bytes;
  }

  // --- Helper Encodings ---

  static List<int> _encodeLine(String text) {
    final clean = sanitizeAscii(text);
    return latin1.encode('$clean\n');
  }

  static String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';

  static String _formatNumber(int number) {
    final s = number.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buffer.write(s[i]);
      count++;
      if (count % 3 == 0 && i > 0 && s[i - 1] != '-') {
        buffer.write('.');
      }
    }
    return buffer.toString().split('').reversed.join();
  }

  static String _formatPaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Tunai';
      case 'qris':
        return 'QRIS';
      case 'transfer':
        return 'Transfer Bank';
      case 'other':
      default:
        return 'Lainnya';
    }
  }
}

