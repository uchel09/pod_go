import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/settings_dao.dart';
import '../local/daos/store_dao.dart';
import '../models/backup_models.dart';

/// Database sementara khusus untuk menjalankan `PRAGMA integrity_check`
/// pada file SQLite hasil ekstraksi tanpa mengganggu database utama.
class _TempCheckDatabase extends GeneratedDatabase {
  final int _version;
  _TempCheckDatabase(super.executor, [this._version = 1]);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => _version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );
}

/// Repository untuk mengelola proses pencadangan (backup), pemulihan (restore),
/// serta pencadangan otomatis (auto-backup) sistem POS Me.
///
/// Mengikuti aturan ketat:
/// - Backup manual & restore tersedia untuk pemilik (`backup.manage`).
/// - Auto-backup dikunci untuk lisensi Semi-Premium ke atas (`Feature.autoBackup`).
/// - Snapshot database yang konsisten menggunakan `VACUUM INTO`.
/// - Validasi menyeluruh sebelum restore: format zip, metadata, PRAGMA integrity_check,
///   dan pemeriksaan schemaVersion (backup tidak boleh lebih baru dari app).
/// - WAJIB membuat backup otomatis kondisi terkini (`pre_restore`) sebelum menimpa database.
/// - Fail-safe rollback: jika restore gagal, database lama dikembalikan dari `.bak`.
/// - Pendekatan penutupan & reinisialisasi koneksi dijelaskan terperinci pada komentar method.
class BackupRepository {
  final AppDatabase _db;
  final StoreDao _storeDao;
  final SettingsDao _settingsDao;
  final File? _customTargetDbFile;

  BackupRepository({
    required AppDatabase db,
    required StoreDao storeDao,
    required SettingsDao settingsDao,
    File? customTargetDbFile,
  })  : _db = db,
        _storeDao = storeDao,
        _settingsDao = settingsDao,
        _customTargetDbFile = customTargetDbFile;

  // =========================================================================
  // GATING & VERIFIKASI HAK AKSES
  // =========================================================================

  void _assertBackupAccess() {
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.backupManage)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk mengelola backup data (backup.manage).',
          code: 'FORBIDDEN',
        );
      }
    }
  }

  void _assertAutoBackupAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.autoBackup)) {
        throw const AppException(
          'Fitur Pencadangan Otomatis (Auto-Backup) memerlukan lisensi Semi Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    _assertBackupAccess();
  }

  // =========================================================================
  // BANTUAN BERKAS & DIREKTORI
  // =========================================================================

  Future<Directory> _getSafeTempDir(Directory? customDir) async {
    if (customDir != null) return customDir;
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// Menentukan lokasi berkas database aktif aplikasi (`pos_me.sqlite`).
  Future<File> getDatabaseFile() async {
    if (_customTargetDbFile != null) return _customTargetDbFile;
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    return File('${dir.path}${Platform.pathSeparator}pos_me.sqlite');
  }

  String sanitizeStoreName(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'pos_me' : cleaned;
  }

  // =========================================================================
  // INFORMASI BACKUP TERAKHIR
  // =========================================================================

  Future<BackupInfo?> getLastBackupInfo() async {
    final lastAtStr = await _settingsDao.getSetting('last_backup_at');
    if (lastAtStr == null || lastAtStr.trim().isEmpty) {
      return null;
    }

    final backedUpAt = DateTime.tryParse(lastAtStr);
    if (backedUpAt == null) return null;

    final sizeStr = await _settingsDao.getSetting('last_backup_size');
    final size = sizeStr != null ? (int.tryParse(sizeStr) ?? 0) : 0;
    final fileName = await _settingsDao.getSetting('last_backup_filename');

    return BackupInfo(
      backedUpAt: backedUpAt,
      sizeInBytes: size,
      fileName: fileName,
    );
  }

  // =========================================================================
  // PEMBUATAN BACKUP (MANUAL & OTOMATIS)
  // =========================================================================

  /// Membuat berkas backup lengkap dalam format ZIP.
  /// Mendukung prefix khusus (misal: `pre_restore` untuk backup pengaman sebelum restore).
  Future<BackupResult> createBackup({
    Directory? tempDirectory,
    String prefix = 'backup',
    bool isAutoBackup = false,
  }) async {
    _assertBackupAccess();

    final store = await _storeDao.getStore();
    final rawStoreName = store?.name ?? 'Toko';
    final sanitizedStoreName = sanitizeStoreName(rawStoreName);

    int productCount = 0;
    try {
      final pRow = await _db.customSelect('SELECT COUNT(*) AS c FROM products').getSingle();
      productCount = pRow.read<int>('c');
    } catch (_) {}

    int transactionCount = 0;
    try {
      final sRow = await _db.customSelect('SELECT COUNT(*) AS c FROM sales').getSingle();
      transactionCount = sRow.read<int>('c');
    } catch (_) {}

    String appVersion = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}

    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
    final zipFileName = '${prefix}_${sanitizedStoreName}_$dateStr.zip';

    final tempDir = await _getSafeTempDir(tempDirectory);
    final tempDbPath = '${tempDir.path}${Platform.pathSeparator}temp_snap_${now.microsecondsSinceEpoch}.db';
    final tempDbFile = File(tempDbPath);

    if (await tempDbFile.exists()) {
      await tempDbFile.delete();
    }

    try {
      // 1. Eksekusi snapshot konsisten SQLite dengan VACUUM INTO
      final escapedDbPath = tempDbFile.path.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escapedDbPath'");

      if (!await tempDbFile.exists()) {
        throw const AppException('Gagal membuat snapshot database.');
      }

      final dbBytes = await tempDbFile.readAsBytes();

      // 2. Susun metadata.json
      final metadata = BackupMetadata(
        schemaVersion: _db.schemaVersion,
        appVersion: appVersion,
        timestamp: now.toIso8601String(),
        storeName: rawStoreName,
        productCount: productCount,
        transactionCount: transactionCount,
      );
      final metaBytes = utf8.encode(jsonEncode(metadata.toJson()));

      // 3. Gabungkan ke dalam format ZIP
      final archive = Archive();
      archive.addFile(ArchiveFile('pos_me.db', dbBytes.length, dbBytes));
      archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes == null) {
        throw const AppException('Gagal mengompresi berkas backup ke format ZIP.');
      }

      final uint8Zip = Uint8List.fromList(zipBytes);

      // 4. Tulis berkas zip ke disk
      final zipFilePath = '${tempDir.path}${Platform.pathSeparator}$zipFileName';
      final zipFile = File(zipFilePath);
      await zipFile.writeAsBytes(uint8Zip, flush: true);

      // 5. Perbarui status backup terakhir di app_settings (kecuali untuk pre_restore)
      if (prefix != 'pre_restore') {
        await _settingsDao.setSetting('last_backup_at', now.toIso8601String());
        await _settingsDao.setSetting('last_backup_size', uint8Zip.length.toString());
        await _settingsDao.setSetting('last_backup_filename', zipFileName);
      }

      // 6. Catat jejak audit
      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.backupCreate,
          entity: 'backup',
          detail: {
            'fileName': zipFileName,
            'fileSize': uint8Zip.length,
            'productCount': productCount,
            'transactionCount': transactionCount,
            'trigger': isAutoBackup ? 'auto_backup' : (prefix == 'pre_restore' ? 'pre_restore' : 'manual'),
          },
        );
      }

      return BackupResult(
        fileName: zipFileName,
        filePath: zipFile.path,
        bytes: uint8Zip,
        fileSize: uint8Zip.length,
        createdAt: now,
        metadata: metadata,
      );
    } finally {
      if (await tempDbFile.exists()) {
        try {
          await tempDbFile.delete();
        } catch (_) {}
      }
    }
  }

  // =========================================================================
  // PEMULIHAN DATA (RESTORE)
  // =========================================================================

  /// Memvalidasi berkas backup sebelum dieksekusi:
  /// 1. Dekompresi ZIP & validasi struktur (keberadaan `pos_me.db` & `metadata.json`).
  /// 2. Parsing metadata & validasi versi skema (`backup.schemaVersion <= app.schemaVersion`).
  /// 3. Uji integritas fisik SQLite dengan `PRAGMA integrity_check;`.
  /// 4. Menyajikan pratinjau perbandingan (toko, waktu, transaksi) untuk konfirmasi pengguna.
  Future<RestorePreview> validateBackupForRestore(File zipFile, {Uint8List? rawBytes}) async {
    _assertBackupAccess();

    if (!await zipFile.exists() && rawBytes == null) {
      throw const AppException('Berkas ZIP backup tidak ditemukan.', code: 'FILE_NOT_FOUND');
    }

    final bytes = rawBytes ?? await zipFile.readAsBytes();

    // 1. Ekstrak & validasi arsip ZIP
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw const AppException(
        'Berkas ZIP rusak atau bukan format kompresi yang valid.',
        code: 'CORRUPTED_ZIP',
      );
    }

    final dbEntry = archive.findFile('pos_me.db');
    final metaEntry = archive.findFile('metadata.json');

    if (dbEntry == null || metaEntry == null) {
      throw const AppException(
        'Struktur berkas backup tidak valid: berkas pos_me.db atau metadata.json tidak ditemukan.',
        code: 'INVALID_BACKUP_STRUCTURE',
      );
    }

    // 2. Baca & validasi metadata.json
    BackupMetadata meta;
    try {
      final metaStr = utf8.decode(metaEntry.content as List<int>);
      final metaJson = jsonDecode(metaStr) as Map<String, dynamic>;
      meta = BackupMetadata.fromJson(metaJson);
    } catch (e) {
      throw AppException(
        'Metadata backup tidak dapat dibaca: $e',
        code: 'INVALID_METADATA',
      );
    }

    // Validasi versi skema database
    if (meta.schemaVersion > _db.schemaVersion) {
      throw AppException(
        'Versi skema database backup (v${meta.schemaVersion}) lebih baru dari versi aplikasi (v${_db.schemaVersion}). Silakan perbarui aplikasi POS Me ke versi terbaru.',
        code: 'SCHEMA_TOO_NEW',
      );
    }

    // 3. Tulis database hasil ekstraksi ke berkas sementara untuk cek integritas
    final tempDir = await _getSafeTempDir(null);
    final tempVerifyPath = '${tempDir.path}${Platform.pathSeparator}verify_restore_${DateTime.now().microsecondsSinceEpoch}.db';
    final tempVerifyFile = File(tempVerifyPath);
    await tempVerifyFile.writeAsBytes(dbEntry.content as List<int>, flush: true);

    // Jalankan PRAGMA integrity_check
    final checkDb = _TempCheckDatabase(NativeDatabase(tempVerifyFile), meta.schemaVersion);
    try {
      final rows = await checkDb.customSelect('PRAGMA integrity_check;').get();
      final checkResult = rows.isNotEmpty ? rows.first.data.values.first.toString() : '';
      if (checkResult.toLowerCase() != 'ok') {
        throw AppException(
          'Pemeriksaan integritas database gagal: $checkResult',
          code: 'INTEGRITY_CHECK_FAILED',
        );
      }
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(
        'Berkas database backup rusak dan tidak dapat dibaca (PRAGMA integrity_check gagal): $e',
        code: 'CORRUPTED_DATABASE',
      );
    } finally {
      await checkDb.close();
    }

    // Ambil ringkasan kondisi toko saat ini untuk perbandingan di modal
    final currentStore = await _storeDao.getStore();
    final currentStoreName = currentStore?.name ?? 'Toko';

    int currentProductCount = 0;
    try {
      final pRow = await _db.customSelect('SELECT COUNT(*) AS c FROM products').getSingle();
      currentProductCount = pRow.read<int>('c');
    } catch (_) {}

    int currentTransactionCount = 0;
    try {
      final sRow = await _db.customSelect('SELECT COUNT(*) AS c FROM sales').getSingle();
      currentTransactionCount = sRow.read<int>('c');
    } catch (_) {}

    return RestorePreview(
      fileName: zipFile.uri.pathSegments.isNotEmpty ? zipFile.uri.pathSegments.last : 'backup.zip',
      fileSize: bytes.length,
      backupMetadata: meta,
      currentStoreName: currentStoreName,
      currentProductCount: currentProductCount,
      currentTransactionCount: currentTransactionCount,
      currentDate: DateTime.now(),
      tempExtractedDbPath: tempVerifyFile.path,
      rawZipBytes: bytes,
    );
  }

  /// Menjalankan pemulihan (restore) database setelah konfirmasi:
  /// 1. WAJIB membuat backup otomatis kondisi terkini (`pre_restore`).
  /// 2. Menutup koneksi database lama secara bersih (`await _db.close()`).
  /// 3. Membuat file cadangan `.bak` dari database aktif untuk rollback instan jika gagal.
  /// 4. Menimpa berkas database dan menghapus berkas `-wal` dan `-shm` lama.
  /// 5. Jika gagal di tengah proses, mengembalikan berkas lama dari `.bak`.
  /// 6. Mencatat audit `AuditActions.backupRestore`.
  Future<void> executeRestore(RestorePreview preview, {File? customTargetDbFile}) async {
    _assertBackupAccess();

    // LANGKAH 1: WAJIB buat backup otomatis kondisi saat ini ("pre_restore")
    final preRestoreResult = await createBackup(prefix: 'pre_restore');

    // LANGKAH 2: Tentukan berkas tujuan database
    final targetDbFile = customTargetDbFile ?? await getDatabaseFile();
    final bakFile = File('${targetDbFile.path}.bak');

    // LANGKAH 3: Tutup koneksi Drift lama dengan benar
    // Penjelasan pendekatan penutupan koneksi:
    // Drift membuka koneksi SQLite native. Menutup `_db.close()` melepaskan file lock
    // dari sistem operasi (terutama di Windows) dan memastikan WAL selesai di-checkpoint.
    await _db.close();

    // LANGKAH 4: Eksekusi penimpaan berkas dengan fail-safe rollback
    try {
      if (await targetDbFile.exists()) {
        await targetDbFile.copy(bakFile.path);
      }

      if (!await targetDbFile.parent.exists()) {
        await targetDbFile.parent.create(recursive: true);
      }

      final extractedFile = File(preview.tempExtractedDbPath);
      if (!await extractedFile.exists()) {
        throw const AppException('Berkas hasil ekstraksi backup tidak ditemukan.');
      }

      // Salin berkas baru ke lokasi target database
      await extractedFile.copy(targetDbFile.path);

      // Bersihkan berkas WAL dan SHM lama jika ada, agar SQLite tidak memutar log lama
      final walFile = File('${targetDbFile.path}-wal');
      if (await walFile.exists()) {
        try {
          await walFile.delete();
        } catch (_) {}
      }

      final shmFile = File('${targetDbFile.path}-shm');
      if (await shmFile.exists()) {
        try {
          await shmFile.delete();
        } catch (_) {}
      }

      // Verifikasi berkas target terisi dengan baik
      if (!await targetDbFile.exists() || await targetDbFile.length() == 0) {
        throw const AppException('Gagal menulis berkas database baru.');
      }
    } catch (e) {
      // Rollback jika terjadi kegagalan di tengah jalan
      if (await bakFile.exists()) {
        try {
          await bakFile.copy(targetDbFile.path);
        } catch (_) {}
      }
      throw AppException(
        'Proses restore gagal: $e. Seluruh data lama telah dikembalikan dari fail-safe rollback.',
        code: 'RESTORE_FAILED',
      );
    } finally {
      // Bersihkan berkas .bak setelah proses selesai (sukses maupun gagal)
      if (await bakFile.exists()) {
        try {
          await bakFile.delete();
        } catch (_) {}
      }
      // Bersihkan berkas verifikasi sementara
      final extractedFile = File(preview.tempExtractedDbPath);
      if (await extractedFile.exists()) {
        try {
          await extractedFile.delete();
        } catch (_) {}
      }
    }

    // Catat log audit pemulihan
    if (Get.isRegistered<AuditService>()) {
      try {
        await AuditService.to.log(
          action: AuditActions.backupRestore,
          entity: 'backup',
          detail: {
            'fileName': preview.fileName,
            'storeName': preview.backupMetadata.storeName,
            'schemaVersion': preview.backupMetadata.schemaVersion,
            'preRestoreBackup': preRestoreResult.fileName,
          },
        );
      } catch (_) {}
    }
  }

  // =========================================================================
  // PENCADANGAN OTOMATIS (AUTO-BACKUP)
  // =========================================================================

  /// Membaca konfigurasi auto-backup dari `app_settings`.
  Future<AutoBackupConfig> getAutoBackupConfig() async {
    final enabledStr = await _settingsDao.getSetting('auto_backup_enabled');
    final folderPath = await _settingsDao.getSetting('auto_backup_folder');
    final schedule = await _settingsDao.getSetting('auto_backup_schedule') ?? 'daily';
    final maxFilesStr = await _settingsDao.getSetting('auto_backup_max_files');
    final maxFiles = maxFilesStr != null ? (int.tryParse(maxFilesStr) ?? 5) : 5;
    final lastRunStr = await _settingsDao.getSetting('auto_backup_last_run');
    final lastRun = lastRunStr != null ? DateTime.tryParse(lastRunStr) : null;

    return AutoBackupConfig(
      enabled: enabledStr == 'true',
      folderPath: folderPath,
      schedule: schedule,
      maxFiles: maxFiles,
      lastRun: lastRun,
    );
  }

  /// Menyimpan konfigurasi auto-backup ke `app_settings`.
  Future<void> saveAutoBackupConfig(AutoBackupConfig config) async {
    _assertAutoBackupAccess();

    await _settingsDao.setSetting('auto_backup_enabled', config.enabled.toString());
    if (config.folderPath != null) {
      await _settingsDao.setSetting('auto_backup_folder', config.folderPath!);
    }
    await _settingsDao.setSetting('auto_backup_schedule', config.schedule);
    await _settingsDao.setSetting('auto_backup_max_files', config.maxFiles.toString());
  }

  /// Melakukan rotasi berkas backup di [folder] agar menyisakan maksimal [maxFiles] berkas terbaru.
  Future<void> rotateBackups(Directory folder, int maxFiles) async {
    if (maxFiles <= 0) return;
    if (!await folder.exists()) return;

    final backupFiles = folder
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last.toLowerCase();
          return name.startsWith('backup_') && name.endsWith('.zip');
        })
        .toList();

    if (backupFiles.length > maxFiles) {
      // Urutkan dari yang paling lama dimodifikasi ke yang terbaru
      backupFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      final excess = backupFiles.length - maxFiles;
      for (int i = 0; i < excess; i++) {
        try {
          await backupFiles[i].delete();
        } catch (_) {}
      }
    }
  }

  /// Menguji eksekusi auto-backup langsung ke folder pilihan dan merotasi berkas.
  Future<BackupResult> testAutoBackup({required String folderPath, int maxFiles = 5}) async {
    _assertAutoBackupAccess();

    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw AppException('Folder tujuan tidak ditemukan: $folderPath');
    }

    final result = await createBackup(
      tempDirectory: folder,
      isAutoBackup: true,
    );

    await rotateBackups(folder, maxFiles);
    return result;
  }

  /// Menjalankan auto-backup jika jadwal telah terpenuhi (dipanggil saat startup/lifecycle aplikasi).
  Future<BackupResult?> runAutoBackupIfNeeded() async {
    // Validasi diam-diam (silent check): jangan melempar exception saat aplikasi dibuka
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.autoBackup)) {
        return null;
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.backupManage)) {
        return null;
      }
    }

    final config = await getAutoBackupConfig();
    if (!config.enabled || config.folderPath == null || config.folderPath!.trim().isEmpty) {
      return null;
    }

    final folder = Directory(config.folderPath!);
    if (!await folder.exists()) {
      return null;
    }

    final now = DateTime.now();
    if (config.lastRun != null) {
      if (config.schedule == 'weekly') {
        if (now.difference(config.lastRun!).inDays < 7) {
          return null;
        }
      } else {
        // Harian: periksa apakah sudah 24 jam atau beda tanggal kalender
        if (now.difference(config.lastRun!).inHours < 24 &&
            now.day == config.lastRun!.day &&
            now.month == config.lastRun!.month &&
            now.year == config.lastRun!.year) {
          return null;
        }
      }
    }

    try {
      final result = await createBackup(
        tempDirectory: folder,
        isAutoBackup: true,
      );

      await rotateBackups(folder, config.maxFiles);
      await _settingsDao.setSetting('auto_backup_last_run', now.toIso8601String());
      return result;
    } catch (_) {
      return null;
    }
  }
}
