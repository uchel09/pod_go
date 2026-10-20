import 'dart:typed_data';

/// Metadata yang disimpan di dalam arsip backup (`metadata.json`).
class BackupMetadata {
  final int schemaVersion;
  final String appVersion;
  final String timestamp;
  final String storeName;
  final int productCount;
  final int transactionCount;

  const BackupMetadata({
    required this.schemaVersion,
    required this.appVersion,
    required this.timestamp,
    required this.storeName,
    required this.productCount,
    required this.transactionCount,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'timestamp': timestamp,
        'storeName': storeName,
        'productCount': productCount,
        'transactionCount': transactionCount,
      };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) => BackupMetadata(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        appVersion: json['appVersion'] as String? ?? '1.0.0',
        timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
        storeName: json['storeName'] as String? ?? 'Toko',
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
        transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      );
}

/// Informasi riwayat backup terakhir yang tersimpan di sistem.
class BackupInfo {
  final DateTime backedUpAt;
  final int sizeInBytes;
  final String? fileName;

  const BackupInfo({
    required this.backedUpAt,
    required this.sizeInBytes,
    this.fileName,
  });

  String get formattedSize {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      final kb = sizeInBytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = sizeInBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }

  int get daysAgo => DateTime.now().difference(backedUpAt).inDays;
}

/// Hasil dari proses pembuatan arsip backup.
class BackupResult {
  final String fileName;
  final String filePath;
  final Uint8List bytes;
  final int fileSize;
  final DateTime createdAt;
  final BackupMetadata metadata;

  const BackupResult({
    required this.fileName,
    required this.filePath,
    required this.bytes,
    required this.fileSize,
    required this.createdAt,
    required this.metadata,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      final kb = fileSize / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = fileSize / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }
}

/// Model data pratinjau sebelum restore dijalankan (untuk konfirmasi perbandingan).
class RestorePreview {
  final String fileName;
  final int fileSize;
  final BackupMetadata backupMetadata;
  final String currentStoreName;
  final int currentProductCount;
  final int currentTransactionCount;
  final DateTime currentDate;
  final String tempExtractedDbPath;
  final Uint8List rawZipBytes;

  const RestorePreview({
    required this.fileName,
    required this.fileSize,
    required this.backupMetadata,
    required this.currentStoreName,
    required this.currentProductCount,
    required this.currentTransactionCount,
    required this.currentDate,
    required this.tempExtractedDbPath,
    required this.rawZipBytes,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      final kb = fileSize / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = fileSize / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }
}

/// Konfigurasi auto-backup yang tersimpan di sistem.
class AutoBackupConfig {
  final bool enabled;
  final String? folderPath;
  final String schedule; // 'daily' | 'weekly'
  final int maxFiles; // rotasi simpan N file
  final DateTime? lastRun;

  const AutoBackupConfig({
    required this.enabled,
    this.folderPath,
    this.schedule = 'daily',
    this.maxFiles = 5,
    this.lastRun,
  });

  AutoBackupConfig copyWith({
    bool? enabled,
    String? folderPath,
    String? schedule,
    int? maxFiles,
    DateTime? lastRun,
  }) {
    return AutoBackupConfig(
      enabled: enabled ?? this.enabled,
      folderPath: folderPath ?? this.folderPath,
      schedule: schedule ?? this.schedule,
      maxFiles: maxFiles ?? this.maxFiles,
      lastRun: lastRun ?? this.lastRun,
    );
  }
}
