import 'package:drift/drift.dart' as drift;
import 'package:get/get.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/tier_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/license_dao.dart';

class LicenseRepository {
  final LicenseDao _dao;

  LicenseRepository(this._dao);

  void _assertLicenseManageAccess() {
    if (Get.isRegistered<PermissionService>() &&
        Get.isRegistered<AuthService>()) {
      final auth = AuthService.to;
      if (auth.hasStore && !auth.isSoloMode) {
        if (!PermissionService.to.can(PermissionKeys.licenseManage)) {
          throw const AppException(
            'Akses ditolak: Anda tidak memiliki izin untuk mengelola lisensi toko (license.manage).',
            code: 'FORBIDDEN',
          );
        }
      }
    }
  }

  Future<License?> getActiveLicense() => _dao.getActiveLicense();
  Stream<License?> watchActiveLicense() => _dao.watchActiveLicense();
  Future<int> insertLicense(LicensesCompanion license) {
    _assertLicenseManageAccess();
    return _dao.insertLicense(license);
  }
  Future<bool> updateLicense(LicensesCompanion license) {
    _assertLicenseManageAccess();
    return _dao.updateLicense(license);
  }

  /// Mengatur tier simulasi secara instan (untuk Panel Developer dan Testing)
  Future<int> setSimulatedTier(Tier tier, {Duration? duration}) async {
    _assertLicenseManageAccess();

    final now = DateTime.now();
    final expiresAt = duration != null ? now.add(duration) : null;
    final oldLicense = await _dao.getActiveLicense();
    final oldTier = oldLicense?.tier ?? 'free';

    final id = await _dao.insertLicense(
      LicensesCompanion(
        tier: drift.Value(tier.name),
        source: const drift.Value('simulated'),
        status: const drift.Value('active'),
        issuedAt: drift.Value(now),
        expiresAt: drift.Value(expiresAt),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.licenseTierChanged,
        entity: 'license',
        detail: {
          'oldTier': oldTier,
          'newTier': tier.name,
          'source': 'simulated_instant',
          'expiresAt': expiresAt?.toIso8601String(),
        },
      );
    }

    return id;
  }

  /// Membuat lisensi berstatus kedaluwarsa (expiresAt di masa lalu) untuk pengujian
  Future<int> setExpiredLicense({Tier tier = Tier.semi}) async {
    _assertLicenseManageAccess();

    final now = DateTime.now();
    final expiredDate = now.subtract(const Duration(days: 1));
    final oldLicense = await _dao.getActiveLicense();
    final oldTier = oldLicense?.tier ?? 'free';

    final id = await _dao.insertLicense(
      LicensesCompanion(
        tier: drift.Value(tier.name),
        source: const drift.Value('simulated'),
        status: const drift.Value('active'),
        issuedAt: drift.Value(now.subtract(const Duration(days: 31))),
        expiresAt: drift.Value(expiredDate),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.licenseTierChanged,
        entity: 'license',
        detail: {
          'oldTier': oldTier,
          'newTier': 'free (expired)',
          'source': 'simulated_expired',
          'expiresAt': expiredDate.toIso8601String(),
        },
      );
    }

    return id;
  }

  /// Mengatur ulang lisensi toko ke paket Gratis
  Future<int> resetToFree() async {
    _assertLicenseManageAccess();

    final now = DateTime.now();
    final oldLicense = await _dao.getActiveLicense();
    final oldTier = oldLicense?.tier ?? 'free';

    final id = await _dao.insertLicense(
      LicensesCompanion(
        tier: const drift.Value('free'),
        source: const drift.Value('simulated'),
        status: const drift.Value('active'),
        issuedAt: drift.Value(now),
        expiresAt: const drift.Value(null),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.licenseTierChanged,
        entity: 'license',
        detail: {
          'oldTier': oldTier,
          'newTier': 'free',
          'source': 'reset_to_free',
        },
      );
    }

    return id;
  }
}
