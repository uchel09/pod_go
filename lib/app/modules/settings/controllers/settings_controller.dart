import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/audit/audit_actions.dart';
import '../../../core/config/app_config.dart';
import '../../../core/features/tier_enum.dart';
import '../../../core/permissions/permission_keys.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/printing/printer_manager.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/theme/theme_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/license_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../developer_panel/controllers/developer_panel_controller.dart';

class SettingsController extends GetxController {
  final StoreRepository _storeRepo = Get.find<StoreRepository>();
  final SettingsRepository _settingsRepo = Get.find<SettingsRepository>();
  final AuthService _authService = AuthService.to;
  final ThemeService _themeService = ThemeService.to;
  final PrinterManager _printerManager = PrinterManager.to;
  final LicenseRepository _licenseRepo = Get.find<LicenseRepository>();

  // State Navigasi Grup
  final selectedGroup = 0.obs;
  final isMobileDetailOpen = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  // Grup 1: Toko
  final storeNameController = TextEditingController();
  final storeAddressController = TextEditingController();
  final storePhoneController = TextEditingController();
  final receiptFooterController = TextEditingController();

  // Grup 2: Penjualan
  final allowNegativeStock = false.obs;
  final discountThresholdController = TextEditingController(text: '10');
  final paperWidth = '58'.obs;

  // Grup Pajak (PPN)
  final taxEnabled = false.obs;
  final taxNameController = TextEditingController(text: 'PPN');
  final taxRateController = TextEditingController(text: '11');
  final taxMode = 'exclusive'.obs; // 'exclusive' | 'inclusive'

  // Grup 3: Scanner
  final scannerType = '1d'.obs;

  // Grup 4: Printer (Reactive dari PrinterManager)
  RxString get printerType => _printerManager.printerType;
  RxString get printerTarget => _printerManager.printerTarget;
  String get receiptModeLabel => _printerManager.receiptMode.value.label;

  // Grup 5: Tampilan
  ThemeMode get currentThemeMode => _themeService.themeMode;
  Color get currentPrimaryColor => _themeService.primaryColor;

  // Grup 6: Keamanan
  Rxn<User> get currentUser => _authService.currentUser;
  bool get isSoloMode => _authService.isSoloMode;
  bool get requireLogin => _authService.requireLogin;

  // Grup 7: Backup
  final lastBackupInfo = ''.obs;

  // Grup 8: Lisensi
  Rx<Tier> get currentTier => FeatureGate.to.tier;
  final activeLicenseExpiresAt = Rxn<DateTime>();

  // Grup 9: Tentang
  final appVersion = '1.0.0'.obs;
  bool get isSimulationMode => AppConfig.simulationMode;

  // Hak Akses
  bool get canManageSettings {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.settingsManage);
  }

  bool get canManageBackup {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.backupManage);
  }

  bool get canManageLicense {
    if (!Get.isRegistered<PermissionService>()) return true;
    return PermissionService.to.can(PermissionKeys.licenseManage);
  }

  bool get isDevModeAllowed =>
      AppConfig.simulationMode &&
      (kDebugMode || DeveloperPanelController.isUnlocked.value);

  @override
  void onInit() {
    super.onInit();
    loadAllSettings();
  }

  @override
  void onClose() {
    storeNameController.dispose();
    storeAddressController.dispose();
    storePhoneController.dispose();
    receiptFooterController.dispose();
    discountThresholdController.dispose();
    taxNameController.dispose();
    taxRateController.dispose();
    super.onClose();
  }

  void _showFeedback(
    String title,
    String message, {
    Color? backgroundColor,
    Color? textColor,
  }) {
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

  Future<void> loadAllSettings() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      // 1. Profil Toko
      final store = await _storeRepo.getStore();
      if (store != null) {
        storeNameController.text = store.name;
        storeAddressController.text = store.address ?? '';
        storePhoneController.text = store.phone ?? '';
        scannerType.value = store.scannerType;
      }

      // Footer struk
      final footer =
          await _settingsRepo.getSetting('receipt.footer') ??
          await _settingsRepo.getSetting('receipt_footer');
      receiptFooterController.text =
          footer ?? 'Terima kasih atas kunjungan Anda!';

      // 2. Penjualan
      final negStock = await _settingsRepo.getSetting(
        'pos.allow_negative_stock',
      );
      allowNegativeStock.value = negStock == 'true';

      final threshold = await _settingsRepo.getSetting(
        'audit_discount_threshold',
      );
      if (threshold != null && threshold.isNotEmpty) {
        discountThresholdController.text = threshold;
      }

      final pWidth =
          await _settingsRepo.getSetting(PrinterManager.keyPaperWidth) ??
          await _settingsRepo.getSetting('pos.receipt_width') ??
          '58';
      paperWidth.value = pWidth;

      // 3. Pengaturan Pajak (PPN)
      final tEnabled = await _settingsRepo.getSetting('tax.enabled');
      taxEnabled.value = tEnabled == 'true';

      final tName = await _settingsRepo.getSetting('tax.name');
      taxNameController.text = (tName != null && tName.isNotEmpty)
          ? tName
          : 'PPN';

      final tRate = await _settingsRepo.getSetting('tax.rate_bps');
      if (tRate != null && tRate.isNotEmpty) {
        final bps = int.tryParse(tRate) ?? 1100;
        if (bps % 100 == 0) {
          taxRateController.text = '${bps ~/ 100}';
        } else {
          taxRateController.text = (bps / 100.0).toString();
        }
      } else {
        taxRateController.text = '11';
      }

      final tMode = await _settingsRepo.getSetting('tax.mode');
      if (tMode != null && (tMode == 'exclusive' || tMode == 'inclusive')) {
        taxMode.value = tMode;
      } else {
        taxMode.value = 'exclusive';
      }

      // 4. Backup Info
      final lastBackupAt = await _settingsRepo.getSetting('last_backup_at');
      final lastBackupFile = await _settingsRepo.getSetting(
        'last_backup_filename',
      );
      if (lastBackupAt != null && lastBackupAt.isNotEmpty) {
        final date = DateTime.tryParse(lastBackupAt);
        final dateStr = date != null
            ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
            : lastBackupAt;
        lastBackupInfo.value = '$dateStr (${lastBackupFile ?? 'backup.zip'})';
      } else {
        lastBackupInfo.value = 'Belum pernah dicadangkan';
      }

      // 4. Lisensi Aktif
      final activeLicense = await _licenseRepo.getActiveLicense();
      activeLicenseExpiresAt.value = activeLicense?.expiresAt;

      // 5. Version Info
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion.value = 'v${info.version}+${info.buildNumber}';
      } catch (_) {
        appVersion.value = 'v1.0.0';
      }
    } catch (e) {
      errorMessage.value = 'Gagal memuat pengaturan: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // --- Operasi Toko ---
  Future<void> saveStoreProfile() async {
    final name = storeNameController.text.trim();
    if (name.isEmpty) {
      _showFeedback(
        'Validasi Gagal',
        'Nama toko wajib diisi.',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    if (!canManageSettings) {
      _showFeedback(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengelola profil toko (settings.manage).',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    isLoading.value = true;
    try {
      final current = await _storeRepo.getStore();
      final now = DateTime.now();

      if (current != null) {
        await _storeRepo.updateStore(
          current
              .toCompanion(true)
              .copyWith(
                name: drift.Value(name),
                address: drift.Value(storeAddressController.text.trim()),
                phone: drift.Value(storePhoneController.text.trim()),
                updatedAt: drift.Value(now),
              ),
        );
      } else {
        await _storeRepo.insertStore(
          StoresCompanion(
            name: drift.Value(name),
            address: drift.Value(storeAddressController.text.trim()),
            phone: drift.Value(storePhoneController.text.trim()),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );
      }

      // Simpan footer struk
      final footer = receiptFooterController.text.trim();
      await _settingsRepo.setSetting('receipt.footer', footer);
      await _settingsRepo.setSetting('receipt_footer', footer);

      await _authService.refreshState();

      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.settingsUpdate,
          entity: 'stores',
          detail: {
            'keys': [
              'store_name',
              'store_address',
              'store_phone',
              'receipt_footer',
            ],
          },
        );
      }

      _showFeedback(
        'Berhasil Disimpan',
        'Profil toko dan footer struk telah diperbarui.',
        backgroundColor: Colors.green.shade800,
      );
    } catch (e) {
      _showFeedback(
        'Gagal Menyimpan Profil Toko',
        e.toString(),
        backgroundColor: Colors.red.shade800,
      );
    } finally {
      isLoading.value = false;
    }
  }

  // --- Operasi Penjualan & Lebar Struk ---
  Future<void> saveSalesSettings() async {
    if (!canManageSettings) {
      _showFeedback(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengelola pengaturan penjualan.',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    isLoading.value = true;
    try {
      // 1. Allow negative stock
      await _settingsRepo.setSetting(
        'pos.allow_negative_stock',
        allowNegativeStock.value ? 'true' : 'false',
      );

      // 2. Audit discount threshold
      final threshold = discountThresholdController.text.trim();
      await _settingsRepo.setSetting('audit_discount_threshold', threshold);

      // 3. Lebar struk sinkron ke Pengaturan Printer
      final width = paperWidth.value;
      await _settingsRepo.setSetting(PrinterManager.keyPaperWidth, width);
      await _settingsRepo.setSetting('pos.receipt_width', width);

      final chars = width == '80' ? 48 : 32;
      await _settingsRepo.setSetting(
        PrinterManager.keyCharsPerLine,
        chars.toString(),
      );

      _printerManager.paperWidth.value = width;
      _printerManager.charsPerLine.value = chars;

      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.settingsUpdate,
          entity: 'settings',
          detail: {
            'keys': [
              'pos.allow_negative_stock',
              'audit_discount_threshold',
              'printer.paper_width',
            ],
          },
        );
      }

      _showFeedback(
        'Pengaturan Disimpan',
        'Pengaturan penjualan dan lebar struk ($width mm) berhasil disinkronkan.',
        backgroundColor: Colors.green.shade800,
      );
    } catch (e) {
      _showFeedback(
        'Gagal Menyimpan Pengaturan',
        e.toString(),
        backgroundColor: Colors.red.shade800,
      );
    } finally {
      isLoading.value = false;
    }
  }

  // --- Operasi Pajak (PPN) ---
  Future<void> saveTaxSettings() async {
    if (!canManageSettings) {
      _showFeedback(
        'Akses Ditolak',
        'Anda tidak memiliki izin untuk mengelola pengaturan pajak.',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    final name = taxNameController.text.trim();
    if (name.isEmpty) {
      _showFeedback(
        'Validasi Gagal',
        'Nama pajak wajib diisi.',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    final rateText = taxRateController.text.trim().replaceAll(',', '.');
    final parsedPercent = double.tryParse(rateText);
    if (parsedPercent == null || parsedPercent < 0 || parsedPercent > 100) {
      _showFeedback(
        'Validasi Gagal',
        'Tarif pajak harus berupa angka antara 0% dan 100%.',
        backgroundColor: Colors.red.shade800,
      );
      return;
    }

    final rateBps = (parsedPercent * 100).round().clamp(0, 10000);

    isLoading.value = true;
    try {
      await _settingsRepo.setSetting(
        'tax.enabled',
        taxEnabled.value ? 'true' : 'false',
      );
      await _settingsRepo.setSetting('tax.name', name);
      await _settingsRepo.setSetting('tax.rate_bps', rateBps.toString());
      await _settingsRepo.setSetting('tax.mode', taxMode.value);

      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.settingsUpdate,
          entity: 'settings',
          detail: {
            'keys': ['tax.enabled', 'tax.name', 'tax.rate_bps', 'tax.mode'],
          },
        );
      }

      _showFeedback(
        'Pengaturan Pajak Disimpan',
        'Pajak $name (${rateBps / 100}%, mode ${taxMode.value == 'exclusive' ? 'Eksklusif' : 'Inklusif'}) berhasil diperbarui.',
        backgroundColor: Colors.green.shade800,
      );
    } catch (e) {
      _showFeedback(
        'Gagal Menyimpan Pajak',
        e.toString(),
        backgroundColor: Colors.red.shade800,
      );
    } finally {
      isLoading.value = false;
    }
  }

  // --- Operasi Scanner ---
  Future<void> setScannerType(String type) async {
    if (!canManageSettings) return;

    scannerType.value = type;
    try {
      final store = await _storeRepo.getStore();
      if (store != null) {
        await _storeRepo.updateStore(
          store
              .toCompanion(true)
              .copyWith(
                scannerType: drift.Value(type),
                updatedAt: drift.Value(DateTime.now()),
              ),
        );
        await _authService.refreshState();

        if (Get.isRegistered<AuditService>()) {
          await AuditService.to.log(
            action: AuditActions.settingsUpdate,
            entity: 'stores',
            detail: {
              'keys': ['scanner_type'],
            },
          );
        }

        _showFeedback(
          'Tipe Scanner Diperbarui',
          'Tipe default scanner toko diatur ke ${type.toUpperCase()}.',
          backgroundColor: Colors.blue.shade800,
        );
      }
    } catch (e) {
      _showFeedback(
        'Gagal Mengubah Tipe Scanner',
        e.toString(),
        backgroundColor: Colors.red.shade800,
      );
    }
  }

  // --- Operasi Tampilan ---
  Future<void> setThemeMode(ThemeMode mode) async {
    await _themeService.setThemeMode(mode);
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.settingsUpdate,
        entity: 'settings',
        detail: {
          'keys': ['app_theme_mode'],
        },
      );
    }
  }

  Future<void> setPrimaryColor(Color color) async {
    await _themeService.setPrimaryColor(color);
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.settingsUpdate,
        entity: 'settings',
        detail: {
          'keys': ['app_primary_color'],
        },
      );
    }
  }

  // --- Operasi Keamanan ---
  Future<void> changePassword({
    required String oldSecret,
    required String newSecret,
    required String confirmSecret,
  }) async {
    if (newSecret != confirmSecret) {
      throw const AppException('Konfirmasi password / PIN baru tidak cocok.');
    }
    if (newSecret.trim().length < 4) {
      throw const AppException(
        'Password atau PIN baru minimal 4 karakter/digit.',
      );
    }

    await _authService.changePasswordWithVerification(
      oldSecret: oldSecret,
      newSecret: newSecret,
    );
  }

  String generateRecoveryCode() {
    return CryptoUtils.generateRecoveryCode();
  }

  Future<void> saveRotatedRecoveryCode(String newRecoveryCode) async {
    await _authService.rotateRecoveryCode(newRecoveryCode: newRecoveryCode);
  }

  Future<void> deactivateSoloLogin(String currentSecret) async {
    await _authService.deactivateSoloLogin(currentSecret: currentSecret);
  }

  Future<void> activateSoloLogin({
    required String newSecret,
    required String newRecoveryCode,
  }) async {
    await _authService.activateSoloLogin(
      newSecret: newSecret,
      newRecoveryCode: newRecoveryCode,
    );
  }
}
