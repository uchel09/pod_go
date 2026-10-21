# RELEASE CHECKLIST - POS ME

Dokumen ini adalah panduan verifikasi wajib sebelum merilis aplikasi POS Me ke lingkungan produksi (Google Play Store dan Windows Distribution).

---

## 1. Konfigurasi Mode Produksi & Pembayaran (Kritis)
- [ ] **Nonaktifkan Mode Simulasi**:
  Pastikan `kSimulationMode` pada `lib/app/core/config/app_config.dart` bernilai `false`.
  ```dart
  const bool kSimulationMode = false;
  ```
  > **PERINGATAN**: Jika `kSimulationMode` tetap `true`, pengguna dapat melakukan simulasi checkout dan mendapatkan upgrade tier Gratis ke Semi/Premium secara cuma-cuma tanpa pembayaran sungguhan.
- [ ] **Ganti Provider Entitlement & Payment Gateway**:
  Ganti `SimulatedEntitlementProvider` dan `SimulatedPaymentGateway` pada `InitialBinding` dengan provider pembayaran produksi (misal: Midtrans, Xendit, atau In-App Purchase Google Play Billing).
- [ ] **Pastikan Panel Developer Terkunci**:
  Pada mode rilis (`kReleaseMode`), Panel Developer dan tombol sample data otomatis tidak dapat diakses dan tidak muncul di pengaturan.

---

## 2. Pengujian Hardware & Lingkungan Nyata
- [ ] **Pengujian Backup & Restore di Perangkat Fisik**:
  - Buat backup manual di HP Android dan Windows PC nyata.
  - Pindahkan file `.zip` ke perangkat lain atau folder Google Drive/Dropbox.
  - Lakukan restore dan verifikasi integritas data SQLite (`PRAGMA integrity_check`).
- [ ] **Pengujian Printer Thermal Fisik**:
  - Uji cetak struk via Bluetooth (Android) pada printer 58mm dan 80mm nyata.
  - Uji cetak struk via Windows Spooler / USB printer di Windows nyata.
  - Pastikan auto-cut dan drawer-kick berfungsi jika didukung hardware.
- [ ] **Pengujian Barcode Scanner**:
  - Uji USB HID Barcode Scanner (scanner tembak) pada kasir desktop Windows.
  - Uji kamera scanner di Android dengan berbagai kondisi pencahayaan.

---

## 3. Kebijakan Privasi & Penyimpanan Data
- [ ] **Penjelasan Offline-First & Data Lokal**:
  Beri tahu pengguna secara transparan bahwa data transaksi, inventori, dan log disimpan secara lokal di perangkat (`SQLite native`).
- [ ] **Tanggung Jawab Cadangan Data**:
  Ingatkan pengguna bahwa backup rutin adalah satu-satunya perlindungan terhadap kehilangan data jika perangkat rusak atau hilang.

---

## 4. Build & Signing Android (Google Play Store)
1. **Buat Android Keystore**:
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Konfigurasi `android/key.properties`**:
   Buat file `android/key.properties`:
   ```properties
   storePassword=<PASSWORD_KEYSTORE>
   keyPassword=<PASSWORD_KEY>
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```
3. **Keamanan Git (`.gitignore`)**:
   Pastikan baris berikut ada di `.gitignore`:
   ```gitignore
   *.jks
   *.keystore
   android/key.properties
   ```
   > **JANGAN PERNAH** melakukan commit file keystore atau file `key.properties` ke repository Git!
4. **Build Android App Bundle**:
   ```bash
   flutter build appbundle --release
   ```

---

## 5. Distribusi Windows Desktop
- **Opsi A: MSIX Package (Microsoft Store / Sideload)**:
  - Gunakan package `msix` (`dart run msix:create`).
  - Menghasilkan installer `.msix` yang modern, terisolasi, dan mendukung auto-update via Microsoft Store.
- **Opsi B: Inno Setup (Standalone Setup .exe)**:
  - Jalankan `flutter build windows --release`.
  - Kemas folder `build/windows/runner/Release` menggunakan script Inno Setup (`.iss`) menjadi berkas installer `POS_Me_Setup.exe`.
  - Sertakan SQLite dll / runtime C++ Visual Studio Redistributable.

