import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/local/app_database.dart';
import '../../../data/local/daos/opname_dao.dart';
import '../../utils/currency_formatter.dart';

class OpnamePdfService {
  static Future<Uint8List> generateOpnameReport({
    required Store? store,
    required OpnameDetailEntry detail,
    required bool canViewCost,
  }) async {
    final pdf = pw.Document();

    final dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(detail.date);
    final printDateFormatted = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header Toko & Judul
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      store?.name.toUpperCase() ?? 'POS TOKO UMKM',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (store?.address != null && store!.address!.isNotEmpty)
                      pw.Text(store.address!, style: const pw.TextStyle(fontSize: 10)),
                    if (store?.phone != null && store!.phone!.isNotEmpty)
                      pw.Text('Telp: ${store.phone}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'BERITA ACARA STOCK OPNAME',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Kode: ${detail.code}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Tanggal: $dateFormatted', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Status: ${detail.status.toUpperCase()}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, height: 16),

            // Info Petugas & Catatan
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Penanggung Jawab: ${detail.creatorName ?? "Kasir/Admin"}', style: const pw.TextStyle(fontSize: 10)),
                  if (detail.opname.note != null && detail.opname.note!.isNotEmpty)
                    pw.Text('Catatan: ${detail.opname.note!}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Ringkasan Statistik
            pw.Row(
              children: [
                _buildSummaryCard('Total Item', '${detail.totalItems}', PdfColors.blue700),
                pw.SizedBox(width: 8),
                _buildSummaryCard('Sudah Dihitung', '${detail.countedCount}', PdfColors.teal700),
                pw.SizedBox(width: 8),
                _buildSummaryCard('Item Ada Selisih', '${detail.diffCount}', detail.diffCount > 0 ? PdfColors.orange800 : PdfColors.green700),
                if (canViewCost) ...[
                  pw.SizedBox(width: 8),
                  _buildSummaryCard(
                    'Total Nilai Selisih',
                    formatRupiah(detail.totalDiffValue),
                    detail.totalDiffValue < 0 ? PdfColors.red800 : (detail.totalDiffValue > 0 ? PdfColors.blue800 : PdfColors.grey700),
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 16),

            // Tabel Rincian Produk
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(28),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FixedColumnWidth(48),
                5: const pw.FixedColumnWidth(48),
                6: const pw.FixedColumnWidth(48),
                if (canViewCost) 7: const pw.FlexColumnWidth(1.8),
              },
              children: [
                // Header Tabel
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cellHeader('No'),
                    _cellHeader('Nama Produk'),
                    _cellHeader('Kategori'),
                    _cellHeader('Satuan'),
                    _cellHeader('Sistem', align: pw.TextAlign.center),
                    _cellHeader('Fisik', align: pw.TextAlign.center),
                    _cellHeader('Selisih', align: pw.TextAlign.center),
                    if (canViewCost) _cellHeader('Nilai Selisih', align: pw.TextAlign.right),
                  ],
                ),
                // Rows
                ...detail.items.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  final hasDiff = item.isCounted && item.difference != 0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: hasDiff ? PdfColors.amber50 : (idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                    ),
                    children: [
                      _cellText('$idx', align: pw.TextAlign.center),
                      _cellText(item.product.name, bold: hasDiff),
                      _cellText(item.categoryName ?? '-'),
                      _cellText(item.unitName ?? '-'),
                      _cellText('${item.systemQty}', align: pw.TextAlign.center),
                      _cellText(
                        item.isCounted ? '${item.countedQty}' : 'Belum',
                        align: pw.TextAlign.center,
                        bold: item.isCounted,
                      ),
                      _cellText(
                        item.isCounted
                            ? (item.difference > 0 ? '+${item.difference}' : '${item.difference}')
                            : '-',
                        align: pw.TextAlign.center,
                        bold: hasDiff,
                        color: hasDiff ? (item.difference < 0 ? PdfColors.red800 : PdfColors.blue800) : PdfColors.black,
                      ),
                      if (canViewCost)
                        _cellText(
                          item.isCounted ? formatRupiah(item.differenceValue) : '-',
                          align: pw.TextAlign.right,
                          color: hasDiff ? (item.differenceValue < 0 ? PdfColors.red800 : PdfColors.blue800) : PdfColors.black,
                        ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),

            // Kolom Tanda Tangan
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Petugas Penghitung,', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 48),
                    pw.Text('( ${detail.creatorName ?? "...................."} )', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Penanggung Jawab / Pemilik,', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 48),
                    pw.Text('( .................................... )', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Dicetak pada: $printDateFormatted', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSummaryCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cellHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _cellText(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        textAlign: align,
      ),
    );
  }
}

