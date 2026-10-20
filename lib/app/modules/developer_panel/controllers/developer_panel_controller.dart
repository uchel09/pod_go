import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/audit/audit_actions.dart';
import '../../../core/config/app_config.dart';
import '../../../core/features/tier_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/audit_dao.dart';
import '../../../data/repositories/license_repository.dart';
import '../../../data/services/payment_gateway.dart';

class DeveloperPanelController extends GetxController {
  final LicenseRepository _licenseRepo = Get.find<LicenseRepository>();
  final PaymentGateway _paymentGateway = Get.find<PaymentGateway>();
  final AppDatabase _db = Get.find<AppDatabase>();
  late final AuditDao _auditDao = _db.auditDao;

  /// Global flag untuk mencatat apakah panel developer telah dibuka lewat 7-tap
  static final RxBool isUnlocked = false.obs;
  static int _tapCount = 0;
  static DateTime? _lastTapTime;

  static void registerVersionTap() {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 3)) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    if (_tapCount >= 7) {
      isUnlocked.value = true;
      _tapCount = 0;
      if (Get.context != null) {
        Get.snackbar(
          'Mode Developer Aktif',
          'Akses panel developer simulasi telah terbuka.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
        );
      }
    }
  }

  void _showFeedback(String title, String message,
      {Color? backgroundColor, Color? textColor}) {
    if (Get.context != null) {
      Get.snackbar(
        title,
        message,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: backgroundColor ?? Colors.grey.shade900,
        colorText: textColor ?? Colors.white,
      );
    }
  }

  final RxBool isLoading = false.obs;
  final RxList<AuditLog> auditLogs = <AuditLog>[].obs;
  final RxInt sampleProductCount = 0.obs;
  final RxInt sampleSaleCount = 0.obs;
  final RxString errorMessage = ''.obs;

  Rx<Tier> get currentTier => FeatureGate.to.tier;

  bool get isAccessAllowed =>
      AppConfig.simulationMode && (kDebugMode || isUnlocked.value);

  bool get canManageLicense {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.licenseManage);
  }

  @override
  void onInit() {
    super.onInit();
    if (!isAccessAllowed) {
      errorMessage.value =
          'Akses ditolak: Panel developer hanya dapat dibuka di mode simulasi dengan hak akses developer.';
    } else if (!canManageLicense) {
      errorMessage.value =
          'Akses ditolak: Anda tidak memiliki izin untuk mengelola lisensi toko (license.manage).';
    } else {
      refreshData();
    }
  }

  Future<void> refreshData() async {
    await Future.wait([
      loadAuditLogs(),
      refreshSampleCounts(),
    ]);
  }

  Future<void> refreshSampleCounts() async {
    try {
      final sampleProducts = await (_db.select(_db.products)
            ..where((t) => t.name.like('[SAMPLE]%')))
          .get();
      sampleProductCount.value = sampleProducts.length;

      final sampleSales = await (_db.select(_db.sales)
            ..where((t) => t.invoiceNo.like('INV-SMPL-%')))
          .get();
      sampleSaleCount.value = sampleSales.length;
    } catch (_) {}
  }

  Future<void> loadAuditLogs() async {
    try {
      final logs = await _auditDao.getLogsPage(limit: 50);
      auditLogs.assignAll(logs);
    } catch (_) {}
  }

  Future<void> setInstantTier(Tier tier, {Duration? duration}) async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      await _licenseRepo.setSimulatedTier(
        tier,
        duration: duration ?? const Duration(days: 30),
      );
      await loadAuditLogs();
      _showFeedback(
        'Tier Diperbarui',
        'Sistem diubah ke paket ${tier.displayName}. Fitur langsung aktif.',
        backgroundColor: Colors.green.shade800,
      );
    } catch (e) {
      _showFeedback('Gagal Mengubah Tier', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> simulatePaymentFailure() async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      final dummyPlan = Plan(
        tier: Tier.semi,
        duration: PlanDuration.monthly,
        price: AppConfig.priceSemiMonthly,
      );
      final result = await _paymentGateway.pay(
        dummyPlan,
        simulateFailure: true,
      );
      _showFeedback(
        'Simulasi Gagal Bayar Berhasil',
        result.errorMessage ?? 'Simulasi transaksi ditolak.',
        backgroundColor: Colors.orange.shade800,
      );
    } catch (e) {
      _showFeedback('Kesalahan Simulasi', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> simulateExpiredLicense() async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      await _licenseRepo.setExpiredLicense(tier: Tier.premium);
      await loadAuditLogs();
      _showFeedback(
        'Lisensi Kadaluwarsa Dibuat',
        'Lisensi kedaluwarsa dicatat. FeatureGate otomatis mengevaluasi ke paket Gratis.',
        backgroundColor: Colors.orange.shade800,
      );
    } catch (e) {
      _showFeedback('Gagal Mengatur Lisensi', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> resetToFree() async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      await _licenseRepo.resetToFree();
      await loadAuditLogs();
      _showFeedback(
        'Reset Selesai',
        'Lisensi dikembalikan ke paket Gratis bawaan.',
        backgroundColor: Colors.blue.shade800,
      );
    } catch (e) {
      _showFeedback('Gagal Reset', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> generateSampleData() async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      final now = DateTime.now();
      final currentUserId =
          Get.isRegistered<AuthService>() && AuthService.to.currentUser.value != null
              ? AuthService.to.currentUser.value!.id
              : 1;

      await _db.transaction(() async {
        final productIds = <int>[];
        for (int i = 1; i <= 50; i++) {
          final pId = await _db.into(_db.products).insert(
                ProductsCompanion(
                  name: drift.Value('[SAMPLE] Produk Demo #$i'),
                  barcode: drift.Value('SMPL${i.toString().padLeft(4, '0')}'),
                  sku: drift.Value('SKU-SMPL-$i'),
                  costPrice: drift.Value(5000 + (i * 200)),
                  sellPrice: drift.Value(10000 + (i * 500)),
                  currentStock: const drift.Value(100),
                  minStock: const drift.Value(5),
                  isActive: const drift.Value(true),
                  createdAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              );
          productIds.add(pId);

          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion(
                  uuid: drift.Value('sm-sample-$i-${now.millisecondsSinceEpoch}'),
                  productId: drift.Value(pId),
                  type: const drift.Value('adjustment'),
                  qtyChange: const drift.Value(100),
                  note: const drift.Value('Sample Initial Stock'),
                  createdBy: drift.Value(currentUserId),
                  createdAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              );
        }

        for (int i = 1; i <= 50; i++) {
          final invoiceNo = 'INV-SMPL-${i.toString().padLeft(4, '0')}';
          final pId = productIds[(i - 1) % productIds.length];
          const qty = 2;
          final costPrice = 5000 + (((i - 1) % productIds.length + 1) * 200);
          final sellPrice = 10000 + (((i - 1) % productIds.length + 1) * 500);
          final total = sellPrice * qty;
          final saleTime = now.subtract(Duration(hours: 50 - i));

          final saleId = await _db.into(_db.sales).insert(
                SalesCompanion(
                  uuid: drift.Value('sale-sample-$i-${now.millisecondsSinceEpoch}'),
                  deviceId: const drift.Value('dev-simulated'),
                  invoiceNo: drift.Value(invoiceNo),
                  cashierId: drift.Value(currentUserId),
                  subtotal: drift.Value(total),
                  discount: const drift.Value(0),
                  tax: const drift.Value(0),
                  total: drift.Value(total),
                  paid: drift.Value(total),
                  change: const drift.Value(0),
                  status: const drift.Value('completed'),
                  createdAt: drift.Value(saleTime),
                  updatedAt: drift.Value(saleTime),
                ),
              );

          await _db.into(_db.saleItems).insert(
                SaleItemsCompanion(
                  saleId: drift.Value(saleId),
                  productId: drift.Value(pId),
                  productName: drift.Value(
                      '[SAMPLE] Produk Demo #${((i - 1) % productIds.length) + 1}'),
                  qty: const drift.Value(qty),
                  price: drift.Value(sellPrice),
                  costPrice: drift.Value(costPrice),
                  discount: const drift.Value(0),
                  subtotal: drift.Value(total),
                  createdAt: drift.Value(saleTime),
                  updatedAt: drift.Value(saleTime),
                ),
              );

          await _db.into(_db.payments).insert(
                PaymentsCompanion(
                  saleId: drift.Value(saleId),
                  method: drift.Value(i % 3 == 0
                      ? 'qris'
                      : (i % 3 == 1 ? 'cash' : 'transfer')),
                  amount: drift.Value(total),
                  createdAt: drift.Value(saleTime),
                  updatedAt: drift.Value(saleTime),
                ),
              );
        }
      });

      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.settingsUpdate,
          entity: 'developer',
          detail: {'action': 'generate_sample_data', 'products': 50, 'sales': 50},
        );
      }

      await refreshData();
      _showFeedback(
        'Data Sampel Berhasil Dibuat',
        '50 produk dan 50 transaksi sampel telah ditambahkan.',
        backgroundColor: Colors.green.shade800,
      );
    } catch (e) {
      _showFeedback('Gagal Membuat Data Sampel', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteSampleData() async {
    if (!canManageLicense) return;
    isLoading.value = true;
    try {
      int deletedProducts = 0;
      int deletedSales = 0;

      await _db.transaction(() async {
        final sampleProducts = await (_db.select(_db.products)
              ..where((t) => t.name.like('[SAMPLE]%')))
            .get();
        final sampleProductIds = sampleProducts.map((p) => p.id).toList();

        final sampleSales = await (_db.select(_db.sales)
              ..where((t) => t.invoiceNo.like('INV-SMPL-%')))
            .get();
        final sampleSaleIds = sampleSales.map((s) => s.id).toList();

        deletedProducts = sampleProductIds.length;
        deletedSales = sampleSaleIds.length;

        if (sampleSaleIds.isNotEmpty) {
          await (_db.delete(_db.payments)
                ..where((t) => t.saleId.isIn(sampleSaleIds)))
              .go();
          await (_db.delete(_db.saleItems)
                ..where((t) => t.saleId.isIn(sampleSaleIds)))
              .go();
          await (_db.delete(_db.stockMovements)
                ..where((t) =>
                    t.refTable.equals('sales') & t.refId.isIn(sampleSaleIds)))
              .go();
          await (_db.delete(_db.sales)
                ..where((t) => t.id.isIn(sampleSaleIds)))
              .go();
        }

        if (sampleProductIds.isNotEmpty) {
          await (_db.delete(_db.saleItems)
                ..where((t) => t.productId.isIn(sampleProductIds)))
              .go();
          await (_db.delete(_db.stockMovements)
                ..where((t) => t.productId.isIn(sampleProductIds)))
              .go();
          await (_db.delete(_db.products)..where((t) => t.id.isIn(sampleProductIds))).go();
        }
      });

      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.settingsUpdate,
          entity: 'developer',
          detail: {
            'action': 'delete_sample_data',
            'deletedProducts': deletedProducts,
            'deletedSales': deletedSales,
          },
        );
      }

      await refreshData();
      _showFeedback(
        'Data Sampel Dihapus',
        'Dihapus: $deletedProducts produk & $deletedSales transaksi sampel. Data asli tetap aman.',
        backgroundColor: Colors.blue.shade800,
      );
    } catch (e) {
      _showFeedback('Gagal Menghapus Data Sampel', e.toString(),
          backgroundColor: Colors.red.shade800);
    } finally {
      isLoading.value = false;
    }
  }
}
