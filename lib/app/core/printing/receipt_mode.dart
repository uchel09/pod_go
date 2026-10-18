/// Mode perilaku struk setelah transaksi tersimpan (disimpan di app_settings
/// dengan kunci [ReceiptMode.settingKey]).
///
/// Cetak struk SELALU aksi tambahan setelah transaksi tersimpan; mode ini hanya
/// menentukan apa yang terjadi otomatis, tidak pernah memengaruhi status transaksi.
enum ReceiptMode {
  /// Default. Tampilkan layar sukses dengan pilihan cetak / simpan PDF / selesai.
  ask('ask', 'Tanya setiap transaksi'),

  /// Cetak otomatis ke printer lalu tampilkan layar sukses singkat.
  always('always', 'Selalu cetak otomatis'),

  /// Langsung kembali ke transaksi baru (snackbar "Transaksi tersimpan" + tombol Cetak).
  never('never', 'Jangan cetak (tanpa struk)');

  const ReceiptMode(this.key, this.label);

  /// Kunci pengaturan di tabel app_settings.
  static const String settingKey = 'receipt_mode';

  /// Nilai yang disimpan di app_settings.
  final String key;

  /// Label untuk UI pengaturan.
  final String label;

  /// Mengurai nilai tersimpan; nilai kosong / tidak dikenal kembali ke [ask].
  static ReceiptMode parse(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final mode in ReceiptMode.values) {
      if (mode.key == value) return mode;
    }
    return ReceiptMode.ask;
  }
}

