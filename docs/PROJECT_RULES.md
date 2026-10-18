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

## 11. Pekerjaan Berikutnya
- Retur sebagian (per item) belum dibuat.
- Fase 2 (karyawan, absensi, host-client) dan fase 3 belum dikerjakan.


