# Panduan Printer Thermal ESC/POS & Struk Belanja

Dokumen ini menjelaskan arsitektur, konfigurasi, cara pemasangan perangkat, dan pemecahan masalah (troubleshooting) untuk modul pencetakan struk thermal pada aplikasi POS Offline UMKM.

---

## 1. Ikhtisar Arsitektur

Modul pencetakan struk dirancang dengan arsitektur **Transport Abstraction** dan generator ESC/POS murni (pure Dart) tanpa dependensi eksternal yang memberatkan:

```
                  +-------------------------+
                  |       ReceiptData       | (Neutral Model)
                  +------------+------------+
                               |
                               v
                  +-------------------------+
                  |     PrinterManager      |
                  +------------+------------+
                               |
           +-------------------+-------------------+
           |                                       |
           v                                       v
+----------------------+               +----------------------+
|  EscPosReceiptPrinter|               |   PdfReceiptPrinter  |
+----------+-----------+               +-----------+----------+
           |                                       |
    (Pure Dart Bytes)                              | (pdf / printing)
+----------+-----------+                           v
|   EscPosGenerator    |                   +------------------+
+----------+-----------+                   | OS Print Spooler |
           |                               +------------------+
           v
+----------------------+
|   PrinterTransport   |
+----------+-----------+
           |
   +-------+-------+---------------+
   |               |               |
   v               v               v
+-------------+ +---------------+ +-------------+
|  Bluetooth  | |Windows Spooler| |   Network   |
| Classic SPP | |  (RAW FFI)    | | (TCP 9100)  |
+-------------+ +---------------+ +-------------+
   (Android)       (Windows)       (LAN / WiFi)
```

### Karakteristik Utama:
- **Zero Asset Dependencies:** `EscPosGenerator` tidak memerlukan font file eksternal atau asset CapabilityProfile, sehingga eksekusi instan dan aman offline.
- **Antarmuka Netral `ReceiptData`:** Struktur data struk independen dari vendor printer atau format output.
- **Serialized Print Queue:** Antrean pencetakan dieksekusi secara serial (satu per satu) dengan mekanisme mutex per instance printer, mencegah tabrakan data perintah.
- **Otomatis Reconnect:** 1x auto-reconnect bila koneksi pertama gagal.
- **Audit Logging:** Setiap kegagalan cetak otomatis dicatat di `AuditService` (`action: printer.fail`) tanpa menyertakan data sensitif.

---

## 2. Tipe Koneksi yang Didukung

| Tipe Koneksi | Platform | Deskripsi & Protokol |
| :--- | :--- | :--- |
| **Bluetooth Classic SPP** | Android | Komunikasi Bluetooth Serial Port Profile (SPP / RFCOMM) standar printer thermal portable/mini (contoh: RPP02N, Zijiang ZJ-58, Panda, Iware). |
| **Windows USB / Spooler** | Windows | Pencetakan langsung data mentah (**RAW Datatype**) lewat Windows Print Spooler Win32 API (`OpenPrinter`, `StartDocPrinter`, `WritePrinter`). Bekerja dengan printer USB yang terpasang driver vendor maupun driver "Generic / Text Only". |
| **LAN / Network (TCP)** | Windows & Android | Socket TCP murni ke port default `9100` (port standar ESC/POS RAW network printer / Ethernet / WiFi printer). |
| **PDF Struk (Fallback)** | Windows & Android | Fallback menggunakan preview PDF bawaan OS lewat paket `printing`. Digunakan bila printer hardware belum terpasang atau mengalami gangguan. |

---

## 3. Batasan Perangkat (Unsupported Devices)

> [!WARNING]
> **Modul ini KHUSUS untuk Printer Thermal Struk (ESC/POS).**
> Modul ini **TIDAK MENDUKUNG** printer label barcode berperekat yang menggunakan protokol bahasa label printer seperti:
> - **TSPL** (TSC Barcode Printers)
> - **ZPL** (Zebra Programming Language)
> - **CPCL** (Citizen / Zebra Portable Label)
> - **EPL** (Eltron Programming Language)
>
> Untuk mencetak barcode atau label stiker produk, gunakan fitur **Label Produk PDF** (`lib/app/modules/product_labels/`) yang dirancang untuk dicetak pada kertas stiker A4 atau label thermal via PDF driver.

---

## 4. Panduan Pemasangan & Pairing

### A. Android (Bluetooth Classic SPP)
1. Nyalakan printer thermal Bluetooth Anda.
2. Buka menu **Settings (Pengaturan) > Bluetooth** pada tablet/ponsel Android Anda.
3. Cari perangkat baru (Scan Device), pilih nama printer Anda (contoh: `RPP02N`, `MTP-II`, `POS-58`, atau `InnerPrinter`).
4. Masukkan PIN pairing jika diminta (umumnya `0000` atau `1234`).
5. Buka aplikasi POS, masuk ke menu **Pengaturan > Printer Thermal & Struk**.
6. Pilih jenis koneksi **Bluetooth**.
7. Tekan tombol **Segarkan Perangkat Bluetooth**, lalu pilih printer yang telah dipasangkan dari daftar dropdown.
8. Tekan **Tes Cetak & Penggaris Karakter** untuk menguji printer.

### B. Windows (USB Spooler)
1. Hubungkan printer thermal via kabel USB ke PC/Laptop Windows Anda.
2. Nyalakan printer.
3. Pastikan printer terdaftar di **Windows Settings > Bluetooth & Devices > Printers & Scanners**.
   - *Tips:* Jika menggunakan printer thermal tanpa driver CD, Anda dapat menambahkan printer menggunakan driver bawaan Windows: **Generic > Generic / Text Only**.
4. Buka aplikasi POS, masuk ke menu **Pengaturan > Printer Thermal & Struk**.
5. Pilih jenis koneksi **USB Windows**.
6. Tekan tombol **Segarkan Printer Windows**, lalu pilih nama printer Anda dari daftar dropdown (contoh: `POS-58`, `POS-80`, `Generic / Text Only`).
7. Tekan **Tes Cetak & Penggaris Karakter**.

### C. LAN / Network (Ethernet / WiFi)
1. Hubungkan printer ke router/jaringan lokal yang sama dengan perangkat kasir.
2. Ketahui IP address printer (biasanya tercetak saat printer melakukan self-test feed saat pertama kali dinyalakan).
3. Buka menu **Pengaturan > Printer Thermal & Struk**.
4. Pilih jenis koneksi **LAN (Jaringan)**.
5. Masukkan IP Address printer (contoh: `192.168.1.200`) dan Port (default `9100`).
6. Tekan **Tes Cetak & Penggaris Karakter**.

---

## 5. Pengaturan Lanjutan

| Pengaturan | Pilihan | Penjelasan |
| :--- | :--- | :--- |
| **Lebar Kertas** | 58 mm / 80 mm | Menentukan layout struk. Kertas 58 mm menggunakan 32 kolom, sedangkan 80 mm menggunakan 48 kolom. |
| **Karakter per Baris** | 30 s/d 48 kolom | Dapat disesuaikan dengan kerapatan dot printer (Font A vs Font B). Gunakan hasil print penggaris angka (ruler) untuk memastikan angka tidak terpotong di tepi kanan. |
| **Potong Kertas (Auto-Cut)** | Partial, Penuh, Nonaktif | Mengirimkan perintah pemotong kertas otomatis bagi printer yang memiliki hardware guillotine cutter. |
| **Baris Kosong (Feed)** | 1 s/d 8 baris | Jumlah spasi baris tambahan di akhir struk agar kertas keluar melewati pisau pemotong. |
| **Buka Laci Kasir (Drawer)** | Aktif / Nonaktif | Mengirim sinyal pulse RJ11 (Pin 0 atau Pin 1) ke laci kasir saat transaksi selesai atau saat tombol buka laci ditekan. |
| **Cetak Otomatis** | Aktif / Nonaktif | Jika aktif, aplikasi akan langsung mencetak struk secara otomatis di latar belakang begitu pembayaran kasir diselesaikan. |

---

## 6. Panduan Troubleshooting (Pemecahan Masalah)

### 1. Karakter Rusak / Simbol Aneh (Garbled Characters)
- **Penyebab:** Printer thermal lawas tidak mendukung karakter non-ASCII (Unicode UTF-8 multi-byte seperti emoji atau huruf beraksen).
- **Solusi:** `EscPosGenerator` telah dilengkapi sanitasi karakter otomatis (`sanitizeAscii`) yang mengubah kutip kurung, bullet, dan aksen menjadi karakter ASCII standar 32–126. Pastikan tidak ada karakter biner acak yang dikirimkan.

### 2. Baris Teks Terpotong di Sebelah Kanan atau Turun ke Baris Baru
- **Penyebab:** Konfigurasi *Karakter per Baris* terlalu besar untuk lebar kertas fisik printer Anda.
- **Solusi:**
  1. Cetak struk tes dari menu **Pengaturan Printer**.
  2. Perhatikan baris `PENGGARIS LEBAR: 1234567890123...`.
  3. Cek berapa digit angka yang berhasil dicetak dalam satu baris sebelum terpotong atau berpindah baris.
  4. Ubah angka *Karakter per Baris* di pengaturan sesuai jumlah digit yang pas (misal: kurangi dari 32 ke 30 untuk 58 mm, atau dari 48 ke 42 untuk 80 mm).

### 3. Potong Kertas Macet atau Tidak Berfungsi
- **Penyebab:** Printer tidak memiliki hardware cutter otomatis (kebanyakan printer 58 mm mini/portable hanya memiliki gigi sobek manual).
- **Solusi:** Ubah opsi **Mode Potong Kertas** ke **Nonaktif** dan tambahkan **Baris Kosong (Feed)** menjadi 4 atau 5 baris agar struk keluar cukup panjang untuk disobek manual.

### 4. Koneksi Bluetooth Timeout / Gagal Terhubung
- **Penyebab:** Printer sedang terhubung ke perangkat lain, baterai printer lemah, atau permission Bluetooth di Android belum diberikan.
- **Solusi:**
  - Matikan dan nyalakan ulang printer.
  - Pastikan tidak ada aplikasi POS lain di perangkat yang sedang mengunci koneksi Bluetooth ke printer.
  - Buka pengaturan aplikasi di Android dan pastikan izin *Perangkat di Sekitar (Nearby Devices)* dan *Bluetooth* diizinkan.

### 5. Windows Spooler Gagal Mencetak (Error Code Win32)
- **Penyebab:** Nama printer salah atau antrean Windows Spooler sedang macet (*error status*).
- **Solusi:**
  - Buka Windows Services (`services.msc`), restart layanan **Print Spooler**.
  - Buka **Printers & Scanners** di Windows, pastikan printer berstatus "Ready / Idle" dan tidak ada antrean dokumen tertunda yang error.
  - Pilih kembali printer dari dropdown di aplikasi POS.

