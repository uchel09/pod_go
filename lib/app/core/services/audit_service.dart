import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;

import '../../data/local/app_database.dart';
import '../../data/repositories/audit_repository.dart';
import '../utils/device_id_service.dart';
import 'auth_service.dart';

/// Layanan pencatatan jejak audit (Audit Trail) untuk semua aksi penting/sensitif sistem.
class AuditService extends GetxService {
  static AuditService get to => Get.find<AuditService>();

  final AuditRepository _auditRepo;

  AuditService(this._auditRepo);

  /// Mencatat suatu aksi ke dalam tabel `audit_logs`.
  /// Secara otomatis menyertakan `userId` yang sedang login dan `deviceId`.
  Future<int> log({
    required String action,
    required String entity,
    int? entityId,
    Map<String, dynamic>? detail,
    int? overrideUserId,
  }) async {
    final userId = overrideUserId ??
        (Get.isRegistered<AuthService>() ? AuthService.to.currentUser.value?.id : null);

    final deviceId = Get.isRegistered<DeviceIdService>()
        ? DeviceIdService.to.deviceId
        : 'unknown_device';

    final now = DateTime.now();

    return _auditRepo.insertLog(
      AuditLogsCompanion(
        userId: Value(userId),
        action: Value(action),
        entity: Value(entity),
        entityId: Value(entityId),
        detail: Value(detail != null ? jsonEncode(detail) : null),
        deviceId: Value(deviceId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Mengambil semua riwayat log audit
  Future<List<AuditLog>> getAllLogs() => _auditRepo.getAllLogs();

  /// Mengamati riwayat log audit secara reaktif
  Stream<List<AuditLog>> watchAllLogs() => _auditRepo.watchAllLogs();
}

