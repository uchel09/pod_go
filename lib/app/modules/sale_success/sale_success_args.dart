import '../../core/printing/receipt_printer.dart';

/// Argumen navigasi ke layar sukses transaksi.
class SaleSuccessArgs {
  /// Id transaksi yang SUDAH tersimpan. Layar memuat ulang datanya dari database.
  final int saleId;

  /// Pekerjaan cetak otomatis yang sedang/sudah berjalan (mode "always"), atau null.
  /// Layar hanya MENAMPILKAN statusnya; hasilnya tidak memengaruhi transaksi.
  final Future<PrintResult>? autoPrintJob;

  const SaleSuccessArgs({required this.saleId, this.autoPrintJob});

  /// Layar sukses singkat yang menutup sendiri (mode "always").
  bool get isBrief => autoPrintJob != null;
}

