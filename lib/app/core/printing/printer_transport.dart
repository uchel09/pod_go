/// Interface abstrak untuk layer komunikasi fisik/jaringan printer thermal
abstract class PrinterTransport {
  /// Membuka koneksi ke printer
  Future<void> connect();

  /// Mengirim raw bytes perintah ESC/POS ke printer
  Future<void> write(List<int> bytes);

  /// Menutup koneksi dari printer
  Future<void> disconnect();

  /// Status apakah printer saat ini sedang terhubung
  bool get isConnected;
}

