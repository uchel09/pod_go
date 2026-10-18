import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../routes/app_pages.dart';

class LoginController extends GetxController {
  final AuthService _authService = AuthService.to;
  final UserRepository _userRepo = Get.find<UserRepository>();

  final usernameController = TextEditingController();
  final secretController = TextEditingController();

  final obscureSecret = true.obs;
  final isLoading = false.obs;
  final lockoutRemainingSeconds = 0.obs;
  Timer? _countdownTimer;

  // Recovery dialog controllers
  final recoveryUsernameController = TextEditingController();
  final recoveryCodeController = TextEditingController();
  final newSecretController = TextEditingController();
  final newSecretConfirmController = TextEditingController();
  final newGeneratedRecoveryCode = ''.obs;
  final hasCopiedNewRecoveryCode = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Pre-fill username jika ada owner user
    _initDefaultUsername();
  }

  Future<void> _initDefaultUsername() async {
    final users = await _userRepo.getAllUsers();
    if (users.isNotEmpty && usernameController.text.isEmpty) {
      usernameController.text = users.first.username;
    }
  }

  @override
  void onClose() {
    _countdownTimer?.cancel();
    usernameController.dispose();
    secretController.dispose();
    recoveryUsernameController.dispose();
    recoveryCodeController.dispose();
    newSecretController.dispose();
    newSecretConfirmController.dispose();
    super.onClose();
  }

  void toggleObscureSecret() {
    obscureSecret.value = !obscureSecret.value;
  }

  void _startLockoutCountdown(int seconds) {
    _countdownTimer?.cancel();
    lockoutRemainingSeconds.value = seconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (lockoutRemainingSeconds.value <= 1) {
        timer.cancel();
        lockoutRemainingSeconds.value = 0;
      } else {
        lockoutRemainingSeconds.value--;
      }
    });
  }

  Future<void> login() async {
    final username = usernameController.text.trim();
    final secret = secretController.text;

    if (username.isEmpty || secret.isEmpty) {
      AppException.showErrorSnackbar('Username dan password/PIN tidak boleh kosong.');
      return;
    }

    try {
      isLoading.value = true;
      await _authService.login(username, secret);
      Get.offAllNamed(Routes.HOME);
    } catch (e) {
      final user = await _userRepo.getUserByUsername(username);
      if (user?.lockedUntil != null && DateTime.now().isBefore(user!.lockedUntil!)) {
        final sec = user.lockedUntil!.difference(DateTime.now()).inSeconds;
        _startLockoutCountdown(sec);
      }
      AppException.showErrorSnackbar(e, title: 'Gagal Masuk');
    } finally {
      isLoading.value = false;
    }
  }

  void openRecoveryDialog(BuildContext context) {
    recoveryUsernameController.text = usernameController.text;
    recoveryCodeController.clear();
    newSecretController.clear();
    newSecretConfirmController.clear();
    newGeneratedRecoveryCode.value = CryptoUtils.generateRecoveryCode();
    hasCopiedNewRecoveryCode.value = false;

    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.blue),
            SizedBox(width: 8),
            Text('Pemulihan Akun Owner', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan username dan 16 karakter Recovery Code yang Anda catat saat setup awal.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: recoveryUsernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: recoveryCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Recovery Code (16 Karakter)',
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newSecretController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN / Password Baru (min 4 digit)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newSecretConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi PIN / Password Baru',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery Code Baru Anda:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                      ),
                      const SizedBox(height: 6),
                      Obx(
                        () => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SelectableText(
                              newGeneratedRecoveryCode.value,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Salin Kode',
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: newGeneratedRecoveryCode.value));
                                hasCopiedNewRecoveryCode.value = true;
                                Get.snackbar(
                                  'Tersalin',
                                  'Recovery Code baru disalin ke clipboard.',
                                  snackPosition: SnackPosition.BOTTOM,
                                  duration: const Duration(seconds: 2),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => _executeRecoveryReset(),
            child: const Text('Reset & Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRecoveryReset() async {
    final username = recoveryUsernameController.text.trim();
    final code = recoveryCodeController.text.trim();
    final newSecret = newSecretController.text;
    final newSecretConfirm = newSecretConfirmController.text;

    if (username.isEmpty || code.isEmpty) {
      AppException.showErrorSnackbar('Username dan Recovery Code harus diisi.');
      return;
    }
    if (newSecret.length < 4) {
      AppException.showErrorSnackbar('PIN/Password baru minimal 4 karakter/digit.');
      return;
    }
    if (newSecret != newSecretConfirm) {
      AppException.showErrorSnackbar('Konfirmasi PIN/Password baru tidak cocok.');
      return;
    }

    try {
      final isPin = int.tryParse(newSecret) != null && newSecret.length <= 6;

      await _authService.resetSecretWithRecoveryCode(
        username: username,
        recoveryCode: code,
        newPin: isPin ? newSecret : null,
        newPassword: !isPin ? newSecret : null,
        newRecoveryCode: newGeneratedRecoveryCode.value,
      );

      Get.back(); // Tutup dialog
      secretController.text = newSecret;
      lockoutRemainingSeconds.value = 0;
      _countdownTimer?.cancel();

      Get.snackbar(
        'Berhasil',
        'Password/PIN berhasil diperbarui. Silakan login sekarang.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade800,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      AppException.showErrorSnackbar(e, title: 'Pemulihan Gagal');
    }
  }
}
