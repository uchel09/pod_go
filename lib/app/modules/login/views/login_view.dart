import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_config.dart';
import '../controllers/login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Obx(
                  () => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Icon(Icons.point_of_sale_rounded, size: 54, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        kAppName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Silakan masuk untuk memulai transaksi',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Lockout Banner
                      if (controller.lockoutRemainingSeconds.value > 0) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.error),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_clock, color: theme.colorScheme.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Akun terkunci. Coba lagi dalam ${controller.lockoutRemainingSeconds.value ~/ 60}m ${controller.lockoutRemainingSeconds.value % 60}d.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Form Fields
                      TextFormField(
                        controller: controller.usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: controller.secretController,
                        obscureText: controller.obscureSecret.value,
                        decoration: InputDecoration(
                          labelText: 'PIN atau Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              controller.obscureSecret.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: controller.toggleObscureSecret,
                          ),
                        ),
                        onFieldSubmitted: (_) => controller.login(),
                      ),
                      const SizedBox(height: 24),

                      // Login Button
                      FilledButton(
                        onPressed: (controller.isLoading.value || controller.lockoutRemainingSeconds.value > 0)
                            ? null
                            : controller.login,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: controller.isLoading.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Masuk ke Kasir', style: TextStyle(fontSize: 15)),
                      ),
                      const SizedBox(height: 16),

                      // Recovery Button
                      TextButton.icon(
                        onPressed: () => controller.openRecoveryDialog(context),
                        icon: const Icon(Icons.help_outline, size: 18),
                        label: const Text('Lupa password? Pakai Recovery Code'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
