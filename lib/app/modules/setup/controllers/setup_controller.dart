import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Value;

import '../../../core/features/feature_enum.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/seeders/master_data_seeder.dart';
import '../../../data/seeders/role_seeder.dart';
import '../../../routes/app_pages.dart';

class SetupController extends GetxController {
  final StoreRepository _storeRepo = Get.find<StoreRepository>();
  final UserRepository _userRepo = Get.find<UserRepository>();
  final RoleRepository _roleRepo = Get.find<RoleRepository>();

  final currentStep = 0.obs;
  final isLoading = false.obs;

  // Step 1: Info Toko
  final storeNameController = TextEditingController();
  final storeAddressController = TextEditingController();
  final storePhoneController = TextEditingController();

  // Step 2: Mode
  final selectedMode = 'solo'.obs; // 'solo' | 'team'

  // Step 3: Owner & Pengamanan
  final ownerNameController = TextEditingController(text: 'Owner');
  final ownerUsernameController = TextEditingController(text: 'owner');
  final securityType = 'none'.obs; // 'none' | 'pin' | 'password'

  final pinController = TextEditingController();
  final pinConfirmController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordConfirmController = TextEditingController();

  final recoveryCode = ''.obs;
  final hasRecordedRecoveryCode = false.obs;

  @override
  void onInit() {
    super.onInit();
    recoveryCode.value = CryptoUtils.generateRecoveryCode();
  }

  @override
  void onClose() {
    storeNameController.dispose();
    storeAddressController.dispose();
    storePhoneController.dispose();
    ownerNameController.dispose();
    ownerUsernameController.dispose();
    pinController.dispose();
    pinConfirmController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
    super.onClose();
  }

  void selectMode(String mode) {
    if (mode == 'team') {
      if (!FeatureGate.to.isEnabled(Feature.teamManagement)) {
        Get.defaultDialog(
          title: 'Fitur Mode Tim (Premium)',
          middleText:
              'Mode Tim memungkinkan multi-user kasir dan otorisasi terpisah. Fitur ini memerlukan lisensi Premium.\n\nSaat ini sistem akan menggunakan Mode Solo (dapat di-upgrade nanti di Pengaturan).',
          textConfirm: 'Paham',
          confirmTextColor: Colors.white,
          onConfirm: () => Get.back(),
        );
        selectedMode.value = 'solo';
        return;
      }
    }
    selectedMode.value = mode;
  }

  void setSecurityType(String type) {
    securityType.value = type;
    if (type != 'none' && recoveryCode.value.isEmpty) {
      recoveryCode.value = CryptoUtils.generateRecoveryCode();
    }
  }

  void copyRecoveryCode() {
    Clipboard.setData(ClipboardData(text: recoveryCode.value));
    Get.snackbar(
      'Tersalin',
      'Recovery Code berhasil disalin ke clipboard.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  bool validateStep1() {
    final name = storeNameController.text.trim();
    if (name.isEmpty) {
      AppException.showErrorSnackbar('Nama toko wajib diisi.');
      return false;
    }
    return true;
  }

  bool validateStep3() {
    final ownerName = ownerNameController.text.trim();
    final username = ownerUsernameController.text.trim();

    if (ownerName.isEmpty) {
      AppException.showErrorSnackbar('Nama pemilik wajib diisi.');
      return false;
    }
    if (username.isEmpty) {
      AppException.showErrorSnackbar('Username wajib diisi.');
      return false;
    }

    if (securityType.value == 'pin') {
      final pin = pinController.text.trim();
      final pinConfirm = pinConfirmController.text.trim();
      if (pin.length < 4 || pin.length > 6) {
        AppException.showErrorSnackbar('PIN harus terdiri dari 4 sampai 6 digit.');
        return false;
      }
      if (pin != pinConfirm) {
        AppException.showErrorSnackbar('Konfirmasi PIN tidak cocok.');
        return false;
      }
      if (!hasRecordedRecoveryCode.value) {
        AppException.showErrorSnackbar('Anda wajib mencatat Recovery Code dan mencentang konfirmasi.');
        return false;
      }
    } else if (securityType.value == 'password') {
      final pass = passwordController.text;
      final passConfirm = passwordConfirmController.text;
      if (pass.length < 6) {
        AppException.showErrorSnackbar('Password minimal 6 karakter.');
        return false;
      }
      if (pass != passConfirm) {
        AppException.showErrorSnackbar('Konfirmasi password tidak cocok.');
        return false;
      }
      if (!hasRecordedRecoveryCode.value) {
        AppException.showErrorSnackbar('Anda wajib mencatat Recovery Code dan mencentang konfirmasi.');
        return false;
      }
    }

    return true;
  }

  void nextStep() {
    if (currentStep.value == 0) {
      if (!validateStep1()) return;
      currentStep.value = 1;
    } else if (currentStep.value == 1) {
      currentStep.value = 2;
    }
  }

  void previousStep() {
    if (currentStep.value > 0) {
      currentStep.value--;
    }
  }

  Future<void> finishSetup() async {
    if (!validateStep3()) return;

    try {
      isLoading.value = true;

      final requireLogin = securityType.value != 'none';
      String? passwordHash;
      String? pinHash;
      String? recoveryCodeHash;

      if (securityType.value == 'pin') {
        pinHash = CryptoUtils.hashSecret(pinController.text.trim());
        recoveryCodeHash = CryptoUtils.hashSecret(
          CryptoUtils.normalizeCode(recoveryCode.value),
        );
      } else if (securityType.value == 'password') {
        passwordHash = CryptoUtils.hashSecret(passwordController.text);
        recoveryCodeHash = CryptoUtils.hashSecret(
          CryptoUtils.normalizeCode(recoveryCode.value),
        );
      }

      // 1. Seed default roles (Owner, Admin, Kasir, Gudang, Crew) & Master Data
      await RoleSeeder.seedDefaultRoles(_roleRepo);
      await MasterDataSeeder.seed(Get.find<CategoryRepository>(), Get.find<UnitRepository>());
      final ownerRole = await _roleRepo.getRoleByName('Owner');
      final int ownerRoleId = ownerRole!.id;

      // 2. Simpan toko
      await _storeRepo.insertStore(
        StoresCompanion(
          name: Value(storeNameController.text.trim()),
          address: Value(
            storeAddressController.text.trim().isEmpty ? null : storeAddressController.text.trim(),
          ),
          phone: Value(
            storePhoneController.text.trim().isEmpty ? null : storePhoneController.text.trim(),
          ),
          mode: Value(selectedMode.value),
          requireLogin: Value(requireLogin),
        ),
      );

      // 3. Simpan akun owner
      final ownerUserId = await _userRepo.insertUser(
        UsersCompanion(
          username: Value(ownerUsernameController.text.trim().toLowerCase()),
          displayName: Value(ownerNameController.text.trim()),
          passwordHash: Value(passwordHash),
          pinHash: Value(pinHash),
          recoveryCodeHash: Value(recoveryCodeHash),
          roleId: Value(ownerRoleId),
          isActive: const Value(true),
        ),
      );

      // 4. Update AuthService state
      await AuthService.to.refreshState();

      if (!requireLogin) {
        final ownerUser = await _userRepo.getUserById(ownerUserId);
        AuthService.to.currentUser.value = ownerUser;
      }

      // 5. Masuk ke beranda
      Get.offAllNamed(Routes.HOME);
    } catch (e) {
      AppException.showErrorSnackbar(e, title: 'Gagal Menyimpan Setup');
    } finally {
      isLoading.value = false;
    }
  }
}
