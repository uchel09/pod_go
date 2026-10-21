# BATASAN & FITUR DITUNDA (KNOWN LIMITATIONS) - POS ME

Dokumen ini mencatat batasan teknis yang diketahui dan daftar fitur yang sengaja ditunda pada Fase 1 aplikasi POS Me.

---

## 1. Batasan Platform & Hardware
- **Windows Tanpa Scan Kamera**:
  Pemindaian barcode via kamera hanya didukung di Android (via `mobile_scanner`). Di Windows Desktop, pemindaian barcode dilakukan menggunakan USB/Bluetooth HID Barcode Scanner fisik (scanner tembak/keyboard emulation).
- **Printer Label Belum Didukung**:
  Pencetakan label barcode saat ini menghasilkan berkas dokumen PDF ukuran kertas label standar (A4 / custom grid) yang siap dicetak ke printer biasa. Pengiriman langsung ke printer label khusus (TSPL / ZPL command) belum didukung secara native.
- **Auto-Backup Terbatas**:
  Fitur Auto-Backup (tersedia di Semi-Premium ke atas) dieksekusi secara lokal saat aplikasi dibuka atau ditutup, serta rotasi otomatis N file terbaru. Auto-backup berbasis background service 24 jam saat aplikasi mati tidak didukung tanpa integrasi server cloud.

---

## 2. Fitur Transaksi & Finansial yang Ditunda
- **Retur Sebagian (Partial Return per Item)**:
  Saat ini pembatalan transaksi hanya mendukung **Full Void** (membatalkan seluruh transaksi penjualan). Pengembalian barang sebagian per item atau penukaran barang belum diimplementasikan.
- **Diskon Lanjutan & Pajak (Tax)**:
  Kolom `discount` dan `tax` pada database sudah disediakan dan dihitung di rumus keuangan, namun perlakuan pajak dinamis dan promo diskon bersyarat (diskon bertingkat, kupon) masih bernilai 0 dan ditunda ke fase berikutnya.

---

## 3. Fitur Multi-User & Multi-Perangkat (Fase 2)
- **Fitur Tim & Karyawan Belum Tersedia**:
  Fase 1 difokuskan pada pengoperasian satu perangkat (Mode Solo dan Kasir Terotentikasi). Manajemen tim karyawan, multi-shift, absensi kasir, dan sinkronisasi data host-client (multi-kasir lokal) belum aktif.
- **Sinkronisasi Multi-Device**:
  Aplikasi bersifat offline-first 100% lokal di satu database perangkat. Persiapan kolom UUID dan Device ID sudah dibuat untuk sinkronisasi di masa depan.

