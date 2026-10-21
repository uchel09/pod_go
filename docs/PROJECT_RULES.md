# PROJECT RULES - POS ME

## 1. Deskripsi Aplikasi & Stack
Aplikasi Point of Sale (POS) offline-first yang dirancang khusus untuk Usaha Mikro, Kecil, dan Menengah (UMKM).

- **Target Platform**: Windows Desktop & Android Mobile/Tablet.
- **Framework & Bahasa**: Flutter (Dart dengan Null-Safety penuh).
- **State Management & Routing & DI**: GetX (`get_cli` architecture pattern).
- **Database & Persistence**: Drift (SQLite offline-first).

---

## 2. Alur Arsitektur
Arsitektur aplikasi mengikuti pemisahan tanggung jawab yang ketat dan terstruktur:

```
View  ──>  Controller  ──>  Repository  ──>  DAO / Local DB
```

1. **View (UI Layer)**:
   - Bertanggung jawab hanya pada rendering antarmuka pengguna dan menangkap input/event.
   - Bersifat reaktif terhadap state yang disediakan oleh Controller.
   - Harus responsif untuk layar HP (Android) maupun Desktop (Windows).
   - Tidak boleh mengandung logika bisnis atau pemanggilan database langsung.

2. **Controller (Application/Presentation Logic Layer)**:
   - Mengelola state halaman/komponen (GetxController).
   - Menangani siklus hidup (lifecycle) dan orkestrasi logika presentasi.
   - Selalu menangani status: **Loading**, **Error**, **Empty**, dan **Success**.
   - Berkomunikasi dengan Repository untuk operasi data.

3. **Repository (Domain/Data Layer)**:
   - Berfungsi sebagai *single source of truth* dan abstraksi akses data.
   - Menjembatani Controller dan DAO/data source lokal (atau remote bila ada sinkronisasi).
   - Melakukan mapping dan validasi data transaksi atau entitas bisnis.

4. **DAO - Data Access Object (Persistence Layer)**:
   - Mengelola query langsung ke SQLite via Drift.
   - Menyediakan interface tipe data kuat (type-safe) untuk operasi CRUD tabel.

---

## 3. Aturan Penggunaan GetX CLI (`get_cli`)
- Pembuatan modul, halaman, atau controller **wajib** menggunakan CLI GetX untuk menjaga konsistensi struktur dan routing:
  - Membuat halaman/modul baru: `get create page:nama_modul`
  - Membuat controller: `get create controller:nama on lokasi`
  - Membuat provider/data source: `get create provider:nama`
- **Dilarang** membuat boilerplate page/controller/binding secara manual dari awal.
- File hasil generate dari CLI baru kemudian diedit dan diimplementasikan sesuai kebutuhan.

---

## 4. Aturan Database (Drift)
- **Modifikasi Tabel**:
  Setiap perubahan struktur tabel atau skema database harus mengikuti protokol berikut:
  1. Naikkan `schemaVersion` pada class database.
  2. Implementasikan `MigrationStrategy` (termasuk migrasi `onUpgrade`).
  3. Jalankan code generation:
     ```bash
     dart run build_runner build --delete-conflicting-outputs
     ```
- **Tabel Transaksi**:
  - Semua tabel transaksi **wajib** memiliki kolom `uuid` (UUID string) dan `deviceId` (string pengenal perangkat) untuk integritas identifikasi transaksi dan persiapan sinkronisasi multi-device.

---

## 5. Manajemen Mata Uang & Angka
- Semua nilai nominal uang **wajib** disimpan dalam tipe data integer Rupiah (`int`), **BUKAN** `double` atau floating-point number.
- Hal ini mutlak untuk mencegah kesalahan pembulatan (*precision loss*) pada perhitungan kasir dan akuntansi.
- Format mata uang untuk tampilan UI ditangani oleh utility/formatter khusus (misal: `10000` -> `Rp 10.000`).

---

## 6. Standar Kode & Kualitas
- **Effective Dart**: Mengikuti pedoman konvensi penamaan, gaya kode, dan formatting standar Dart.
- **Konstruktor `const`**: Gunakan `const` pada widget/objek statis semaksimal mungkin untuk performa optimal.
- **Clean Production Code**: Tidak boleh menyisakan kode placeholder sementara atau mock hardcoded yang tidak tertata.
- **Bebas Deprecated API**: Selalu gunakan API terkini dan hindari penggunaan method/class yang sudah didepresiasi.
- **Separation of Concerns**: Logika bisnis murni harus berada di Controller atau Repository, bukan di dalam widget tree.
- **UI Responsif**: Tata letak harus fleksibel menyesuaikan form factor HP (orientasi potret/lanskap Android) serta layar lebar Windows Desktop.

---

## 7. Gate Fitur & Kontrol Izin Akses (RBAC & Feature Gating)
- **Pengecekan Fitur**: Setiap fitur yang bergantung pada lisensi, edisi, atau konfigurasi harus diperiksa melalui:
  ```dart
  FeatureGate.to.isEnabled(...) // atau FeatureGate.to.requireFeature(...)
  ```
- **Pengecekan Hak Akses (RBAC / Permission)**: Setiap hak akses pengguna harus melalui:
  ```dart
  PermissionService.to.can(...)
  ```
- **ATURAN WAJIB DUA LAPIS (Controller/Repository Layer Enforcement)**:
  Setiap aksi sensitif (penjualan, pemberian diskon, void transaksi, ubah harga produk, penyesuaian stok, stock opname, import/export, backup data, manajemen karyawan/role, dsb.) **WAJIB** memvalidasi `PermissionService.to.can(...)` DAN `FeatureGate.to.isEnabled(...)` secara langsung di **Controller** atau **Repository**, **BUKAN HANYA** menyembunyikan tombol di antarmuka (View/UI).
  - Melempar `AppException('Akses ditolak...')` jika hak akses role tidak memenuhi syarat.
  - Memanggil `FeatureGate.to.requireFeature(...)` atau melempar `AppException('Fitur memerlukan lisensi...')` jika tier tidak mencukupi.
- **Pencatatan Jejak Audit (Audit Trail)**:
  Setiap aksi penting (perubahan harga produk, void transaksi kasir, penyesuaian/opname stok, kegagalan login, reset kredensial, perubahan tier lisensi) **WAJIB** dicatat ke tabel `audit_logs` menggunakan:
  ```dart
  AuditService.to.log(...)
  ```
- Dilarang keras membypass pengecekan langsung dengan boolean hardcoded di UI.

---

## 8. Aturan Stok dan Transaksi
- currentStock di products hanyalah cache. Sumber kebenaran adalah stock_movements.
- Setiap perubahan stok WAJIB lewat StockRepository.applyMovement(...) dalam satu database.transaction() bersama pencatatan stock_movements. Dilarang mengubah currentStock langsung.
- Tipe movement: sale, purchase, opname, void, adjustment.
- sale_items menyimpan SNAPSHOT: productName, price, costPrice saat transaksi. Laporan lama tidak boleh berubah saat harga produk diedit.
- Transaksi void tidak dihapus dan tidak bisa diedit.
- Pembelian barang (PurchaseRepository.receive) menambah stok bertipe purchase dan dapat memperbarui costPrice master produk jika toggle aktif.
- Pembatalan pembelian (PurchaseRepository.cancelPurchase) membalikkan stok lewat movement bertipe adjustment (negatif) hanya jika stok saat ini mencukupi. Pembatalan pembelian TIDAK mengembalikan costPrice produk yang sudah diperbarui.
- Stock opname (OpnameRepository.finalize) dijalankan dalam satu database.transaction(): systemQty dihitung ulang dari currentStock terkini produk untuk mencegah race condition dengan penjualan kasir, selisih != 0 dicatat sebagai stock_movements bertipe opname via StockRepository.applyMovement, dan sesi menjadi final (read-only dan tidak dapat dihapus).

## 9. Checkout dan Struk
- Checkout (SaleRepository.checkout) menyimpan transaksi secara atomik dan TIDAK boleh bergantung pada printer atau PDF.
- Cetak struk adalah aksi terpisah dan opsional (receipt_mode: ask/always/never). Kegagalan printer tidak membatalkan atau menggandakan transaksi.
- Tombol Bayar memakai guard isSaving untuk mencegah transaksi ganda.
- Riwayat dikelompokkan per hari berdasar waktu lokal, dihitung lewat query agregat di DAO, dengan pagination.
- Detail printer ada di docs/PRINTER.md. Scanner lewat ScannerService sebagai satu pintu.

## 10. Tier (Simulasi)
- Tier: Gratis (maks 10 produk aktif), Semi Premium (tanpa batas produk, opname, pembelian, import/export, laporan lengkap, auto-backup), Premium (fitur tim).
- Sumber tier lewat abstraksi EntitlementProvider (saat ini SimulatedEntitlementProvider). kSimulationMode di app_config.dart harus false sebelum rilis publik.
- Turun tier: data tidak dihapus; produk di atas batas menjadi read-only.

## 11. Status Fase & Daftar Fitur yang Ditunda
- **Status Proyek Saat Ini**: Fase 1 (Selesai & Dipoles). Mencakup Tier Gratis dan Semi-Premium pada satu perangkat (Windows & Android), Offline-First Drift SQLite, Kasir POS Cepat dengan pintasan keyboard, Struk Thermal ESC/POS & PDF, Impor/Ekspor CSV & Excel, Backup/Restore ZIP, Layar Lisensi & Panel Developer Simulasi.
- **Fitur yang Ditunda (Fase 2 & Selanjutnya - Dilarang Dikerjakan di Fase 1)**:
  1. Multi-user Tim (manajemen karyawan kasir lanjutan, multi-role karyawan, absensi, dan jam kerja).
  2. Arsitektur Host-Client / sinkronisasi multi-kasir lokal.
  3. Retur penjualan sebagian (partial item return / penukaran barang).
  4. Perhitungan pajak dinamis (Tax) dan diskon bersyarat bertingkat (kolom skema `discount` & `tax` tetap dipakai di rumus dengan nilai 0).
  5. Pengiriman instruksi cetak native TSPL/ZPL ke printer label barcode (saat ini memakai ekspor PDF label).

## 12. Aturan Jejak Audit (Audit Trail)
- Log audit (`audit_logs`) bersifat append-only: AuditDao tidak memiliki method update maupun delete.
- Log audit selalu ikut ter-backup saat proses backup database dibuat.
- Fitur ekspor log aktivitas akan disediakan pada Prompt 14.

## 13. Definisi Angka Laporan Keuangan
- **Omzet Bruto**: Jumlah `sales.total` dari transaksi berstatus `completed` (transaksi `void` TIDAK dihitung).
- **Total Retur**: Jumlah `sale_returns.total` dari transaksi retur yang terjadi dalam periode.
- **Penjualan Bersih (Net Sales)**: `Omzet Bruto - Total Retur`.
- **Pajak Bersih (Net Tax)**: `Pajak Penjualan - Pajak Retur (tax_refund)`.
- **Pendapatan Bersih**: `Penjualan Bersih - Pajak Bersih`. (Catatan: diskon sudah memotong subtotal menjadi total di `sales.total`, sedangkan kolom `sales.discount` bernilai 0 sampai fitur diskon aktif).
- **HPP Bersih (Harga Pokok Penjualan)**: `HPP Penjualan - HPP Retur Restock`.
  - HPP Retur HANYA dihitung untuk barang yang opsi restock = true.
  - Barang rusak/tidak kembali ke stok (`restock = false`) TIDAK mengurangi HPP karena barang tersebut tetap hilang/menjadi beban inventaris.
- **Laba Kotor**: `Pendapatan Bersih - HPP Bersih`.
- **Pengeluaran Operasional (Expenses)**: Jumlah `expenses.amount` dari transaksi pengeluaran berstatus `active` dalam periode (transaksi `void` TIDAK dihitung).
- **Laba Bersih**: `Laba Kotor - Pengeluaran Operasional`.
- Rumus ini wajib konsisten di semua komponen: DAO, Repository, Dashboard, dan Laporan.

## 14. Aturan Impor Data (CSV & Excel)
- Fitur impor dikunci untuk tier Semi-Premium ke atas (`Feature.importExport`) dan memerlukan izin `PermissionKeys.importManage` (dual-layer check di Controller & Repository).
- Stok awal dari impor dicatat melalui `StockRepository.applyMovement` bertipe `adjustment`.
- Mode update (upsert) tidak menimpa stok produk yang ada kecuali opsi "koreksi stok" dicentang dan `stok_awal` diisi.
- Kode internal produk (`P000123`) dipertahankan saat diimpor dan counter `internal_product_counter` di `app_settings` dinaikkan secara sinkron agar tidak terjadi bentrok kode.
- Eksekusi impor dijalankan dalam `database.transaction()` per batch (~200 baris) dengan parsing toleran format angka/mata uang Rupiah.
- Setiap eksekusi impor dicatat ke `AuditService` dengan action `import.run`.

## 15. Aturan Ekspor Data (CSV & Excel)
- Fitur ekspor dikunci untuk tier Semi-Premium ke atas (`Feature.importExport`) dan memerlukan izin `PermissionKeys.reportExport` (dual-layer check di Controller & Repository).
- Berkas CSV wajib diawali byte UTF-8 BOM (`[0xEF, 0xBB, 0xBF]`) agar karakter Rupiah dan penulisan teks otomatis terbaca rapi di Microsoft Excel Windows. Berkas Excel diekspor dalam format `.xlsx`.
- Sensor data finansial sensitif:
  - Kolom harga beli produk (`costPrice`) dan pembelian hanya disertakan jika memiliki izin `PermissionKeys.productViewCost`.
  - Kolom harga modal snapshot dan laba kotor pada transaksi penjualan dan laporan lengkap hanya disertakan jika memiliki izin `PermissionKeys.reportViewProfit`.
- Ekspor jejak aktivitas pengguna (`audit_logs`) wajib memvalidasi izin `PermissionKeys.auditView`.
- Setiap ekspor data dicatat secara otomatis ke `AuditService` dengan action `export.run` (merekam jenis entitas, format file, rentang tanggal, dan jumlah baris tanpa membocorkan data rahasia/finansial).

## 16. Aturan Kustomisasi Pajak (PPN)
- **Konfigurasi Toko**: Disimpan di `app_settings` (`tax_enabled`, `tax_name`, `tax_rate_bps`, `tax_mode`).
- **Skema Basis Poin (BPS)**: Persentase disimpan sebagai integer (1100 = 11.00%), tanpa floating-point.
- **Mode Pajak**:
  - `exclusive`: Pajak ditambahkan di atas subtotal (`tax = round(subtotal * rate / 10000)`).
  - `inclusive`: Harga item sudah termasuk pajak (`tax = total - round(total * 10000 / (10000 + rate))`).
- **Izin**: Pengaturan pajak memerlukan `PermissionKeys.settingsManage`.

## 17. Aturan Retur Penjualan (Per Item)
- **Izin & Akses**: Memerlukan izin `PermissionKeys.posReturn` (`pos.return`, default untuk Owner dan Admin) yang diverifikasi di level Controller dan Repository.
- **Nomor Retur**: Berurutan dengan format `RTN-YYYYMMDD-NNNN` (counter harian unik).
- **Mutual Exclusion dengan Void**:
  - Transaksi yang sudah memiliki minimal 1 retur TIDAK dapat dibatalkan (void).
  - Transaksi yang sudah dibatalkan (void) TIDAK dapat diretur.
- **Opsi Restock**:
  - Ditentukan per item (`restock = true / false`).
  - Jika `restock = true`, stok fisik bertambah melalui `StockRepository.applyMovement` bertipe `return`.
  - Jika `restock = false`, stok fisik tidak berubah, dicatat di log audit dan database.
- **Validasi Kuantitas & Nilai Refund**:
  - Jumlah retur kumulatif per item tidak boleh melebihi kuantitas pembelian awal pada `sale_items`.
  - Total pengembalian dana kumulatif tidak boleh melebihi nilai transaksi awal.
  - Pajak dihitung ulang secara proporsional sesuai perbandingan subtotal yang diretur.
- **Audit**: Setiap transaksi retur dicatat ke `audit_logs` dengan aksi `sale.return`.

## 18. Aturan Pengeluaran Operasional & Laba Bersih
- **Gating Lisensi**: Memerlukan lisensi Semi-Premium ke atas (`Feature.expenses`). Pada tier Gratis, menu pengeluaran diberi ikon gembok dan dialihkan ke layar penawaran upgrade (`FeatureGate.to.requireFeature`).
- **Izin & Akses**:
  - Melihat data pengeluaran memerlukan `PermissionKeys.expenseView` (`expense.view`).
  - Mencatat, mengubah, membatalkan pengeluaran, serta mengelola kategori memerlukan `PermissionKeys.expenseManage` (`expense.manage`).
- **Integritas Transaksi**:
  - Pengeluaran tidak dapat dihapus permanen (hard-delete). Transaksi yang salah dibatalkan (void) dengan menyertakan alasan. Hanya pengeluaran berstatus `active` yang dihitung ke laporan keuangan.
  - Perubahan nominal pengeluaran dicatat ke jejak audit (`expense.update`) beserta rincian nilai lama dan baru.
  - Nominal pengeluaran wajib merupakan bilangan bulat positif Rupiah (`amount > 0`).
- **Kategori Pengeluaran**:
  - Kategori bawaan: Listrik, Air, Sewa, Gaji, Transport, Kemasan, Perawatan, Lainnya.
  - Kategori yang sudah memiliki riwayat pengeluaran tidak dapat dihapus, namun dapat dinonaktifkan (`isActive = false`).
- **Audit**: Setiap transaksi dicatat ke `audit_logs` dengan aksi `expense.create`, `expense.update`, atau `expense.void`.




