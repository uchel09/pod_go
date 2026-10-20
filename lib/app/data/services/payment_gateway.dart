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
import '../repositories/license_repository.dart';

/// Durasi paket lisensi
enum PlanDuration {
  monthly,
  yearly;

  Duration get duration => this == PlanDuration.monthly
      ? const Duration(days: 30)
      : const Duration(days: 365);

  String get displayName =>
      this == PlanDuration.monthly ? 'Bulanan (30 Hari)' : 'Tahunan (365 Hari)';
}

/// Model paket langganan lisensi
class Plan {
  final Tier tier;
  final PlanDuration duration;
  final int price; // Integer Rupiah

  const Plan({
    required this.tier,
    required this.duration,
    required this.price,
  });

  String get name => '${tier.displayName} - ${duration.displayName}';
}

/// Hasil transaksi pembayaran paket
class PaymentResult {
  final bool isSuccess;
  final String? transactionId;
  final String? errorMessage;
  final DateTime paidAt;
  final Plan plan;

  const PaymentResult({
    required this.isSuccess,
    this.transactionId,
    this.errorMessage,
    required this.paidAt,
    required this.plan,
  });

  factory PaymentResult.success({
    required Plan plan,
    required String transactionId,
  }) =>
      PaymentResult(
        isSuccess: true,
        transactionId: transactionId,
        paidAt: DateTime.now(),
        plan: plan,
      );

  factory PaymentResult.failure({
    required Plan plan,
    required String errorMessage,
  }) =>
      PaymentResult(
        isSuccess: false,
        errorMessage: errorMessage,
        paidAt: DateTime.now(),
        plan: plan,
      );
}

/// Kontrak abstraksi Gateway Pembayaran.
/// Memungkinkan implementasi simulasi ditukar dengan Midtrans / Xendit / Payment Gateway asli
/// tanpa mengubah alur logika checkout lisensi.
abstract class PaymentGateway {
  Future<PaymentResult> pay(
    Plan plan, {
    String paymentMethod = 'qris',
    bool simulateFailure = false,
  });
}

/// Implementasi simulasi pembayaran lokal tanpa gateway nyata.
/// Menyimpan lisensi baru ke database dan mencatat jejak audit.
class SimulatedPaymentGateway implements PaymentGateway {
  final LicenseRepository _licenseRepo;

  SimulatedPaymentGateway(this._licenseRepo);

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

  @override
  Future<PaymentResult> pay(
    Plan plan, {
    String paymentMethod = 'qris',
    bool simulateFailure = false,
  }) async {
    _assertLicenseManageAccess();

    // Simulasi jeda pemrosesan jaringan perbankan (1-2 detik)
    await Future.delayed(const Duration(milliseconds: 1200));

    if (simulateFailure) {
      return PaymentResult.failure(
        plan: plan,
        errorMessage: 'Pembayaran simulasi ditolak atau saldo tidak mencukupi.',
      );
    }

    final now = DateTime.now();
    final expiresAt = now.add(plan.duration.duration);

    // Ambil tier lama untuk perbandingan jejak audit
    final oldLicense = await _licenseRepo.getActiveLicense();
    final oldTier = oldLicense?.tier ?? 'free';

    // Simpan lisensi aktif baru ke tabel licenses
    await _licenseRepo.insertLicense(
      LicensesCompanion(
        tier: drift.Value(plan.tier.name),
        source: const drift.Value('simulated'),
        status: const drift.Value('active'),
        issuedAt: drift.Value(now),
        expiresAt: drift.Value(expiresAt),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    // Catat ke AuditService (license.tier_changed)
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.licenseTierChanged,
        entity: 'license',
        detail: {
          'oldTier': oldTier,
          'newTier': plan.tier.name,
          'source': 'simulated',
          'method': paymentMethod,
          'price': plan.price,
          'expiresAt': expiresAt.toIso8601String(),
        },
      );
    }

    return PaymentResult.success(
      plan: plan,
      transactionId: 'SIM-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
