import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/auth_service.dart';
import '../utils/app_exception.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  static Future<void> show(BuildContext context) {
    return Get.dialog(const ChangePasswordDialog());
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _newSecretController = TextEditingController();
  final _confirmSecretController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _newSecretController.dispose();
    _confirmSecretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newSecret = _newSecretController.text.trim();
    final confirm = _confirmSecretController.text.trim();

    if (newSecret.length < 4) {
      AppException.showErrorSnackbar('PIN atau Password baru minimal 4 karakter/digit.');
      return;
    }
    if (newSecret != confirm) {
      AppException.showErrorSnackbar('Konfirmasi PIN/Password baru tidak cocok.');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final isPin = int.tryParse(newSecret) != null && newSecret.length <= 6;

      await AuthService.to.changeCurrentPassword(
        newPin: isPin ? newSecret : null,
        newPassword: !isPin ? newSecret : null,
      );

      Get.back();
      Get.snackbar(
        'Berhasil',
        'PIN / Password berhasil diubah.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade800,
        colorText: Colors.white,
      );
    } catch (e) {
      AppException.showErrorSnackbar(e, title: 'Gagal Mengubah Password');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti Password / PIN'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newSecretController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'PIN / Password Baru',
                hintText: 'Min. 4 digit PIN atau huruf',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmSecretController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Ulangi PIN / Password Baru',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}

