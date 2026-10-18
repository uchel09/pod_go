import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/setup_controller.dart';

class SetupView extends GetView<SetupController> {
  const SetupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Awal POS Me'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
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
                      // Step Indicator
                      _buildStepProgress(context),
                      const SizedBox(height: 28),

                      // Step Content
                      if (controller.currentStep.value == 0)
                        _buildStep1(context)
                      else if (controller.currentStep.value == 1)
                        _buildStep2(context)
                      else
                        _buildStep3(context),

                      const SizedBox(height: 32),

                      // Action Buttons
                      _buildActionButtons(context),
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

  Widget _buildStepProgress(BuildContext context) {
    final theme = Theme.of(context);
    final current = controller.currentStep.value;

    return Row(
      children: [
        _buildStepBadge(context, 0, 'Toko', current >= 0, current == 0),
        Expanded(child: Divider(color: current > 0 ? theme.colorScheme.primary : theme.colorScheme.outlineVariant)),
        _buildStepBadge(context, 1, 'Mode', current >= 1, current == 1),
        Expanded(child: Divider(color: current > 1 ? theme.colorScheme.primary : theme.colorScheme.outlineVariant)),
        _buildStepBadge(context, 2, 'Owner', current >= 2, current == 2),
      ],
    );
  }

  Widget _buildStepBadge(BuildContext context, int step, String label, bool isDoneOrActive, bool isActive) {
    final theme = Theme.of(context);

    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isActive
              ? theme.colorScheme.primary
              : isDoneOrActive
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
          child: Text(
            '${step + 1}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isActive
                  ? theme.colorScheme.onPrimary
                  : isDoneOrActive
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Langkah 1: Informasi Toko',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Masukkan identitas usaha Anda. Data ini dicetak di struk nota kasir.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: controller.storeNameController,
          decoration: const InputDecoration(
            labelText: 'Nama Toko *',
            hintText: 'Contoh: Kopi Kenangan Kita',
            prefixIcon: Icon(Icons.storefront_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: controller.storeAddressController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Alamat Toko (Opsional)',
            hintText: 'Jl. Merdeka No. 12, Jakarta',
            prefixIcon: Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: controller.storePhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Nomor Telepon / WhatsApp (Opsional)',
            hintText: '081234567890',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2(BuildContext context) {
    final theme = Theme.of(context);
    final isSolo = controller.selectedMode.value == 'solo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Langkah 2: Pilih Mode Penggunaan',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Pilih cara operasional kasir di toko Anda.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        // Solo Mode Card
        InkWell(
          onTap: () => controller.selectMode('solo'),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSolo ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: isSolo ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: isSolo ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSolo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSolo ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Saya pakai sendiri (Solo)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('Direkomendasikan', style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: theme.colorScheme.primaryContainer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1 perangkat offline. Transaksi kasir instan, login opsional, tanpa repot mengelola banyak user kasir.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Team Mode Card
        InkWell(
          onTap: () => controller.selectMode('team'),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: !isSolo ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: !isSolo ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  !isSolo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: !isSolo ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Saya punya tim (Team)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          Chip(
                            avatar: const Icon(Icons.lock_outline, size: 12),
                            label: const Text('Premium', style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mendukung banyak kasir bergantian, hak akses terpisah, dan shift kasir.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3(BuildContext context) {
    final theme = Theme.of(context);
    final secType = controller.securityType.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Langkah 3: Akun Pemilik (Owner)',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Tentukan identitas dan metode pengamanan akun pemilik.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: controller.ownerNameController,
          decoration: const InputDecoration(
            labelText: 'Nama Lengkap Pemilik *',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: controller.ownerUsernameController,
          decoration: const InputDecoration(
            labelText: 'Username Login *',
            hintText: 'owner',
            prefixIcon: Icon(Icons.alternate_email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Text('Pilihan Pengamanan:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tanpa Password (Instan)'),
              selected: secType == 'none',
              onSelected: (val) => controller.setSecurityType('none'),
            ),
            ChoiceChip(
              label: const Text('PIN (4-6 Digit)'),
              selected: secType == 'pin',
              onSelected: (val) => controller.setSecurityType('pin'),
            ),
            ChoiceChip(
              label: const Text('Password (Min 6 Karakter)'),
              selected: secType == 'password',
              onSelected: (val) => controller.setSecurityType('password'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (secType == 'pin') ...[
          TextFormField(
            controller: controller.pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Buat PIN Baru (4-6 digit) *',
              prefixIcon: Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.pinConfirmController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Ulangi PIN *',
              prefixIcon: Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],

        if (secType == 'password') ...[
          TextFormField(
            controller: controller.passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password Baru (min 6 karakter) *',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.passwordConfirmController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Ulangi Password *',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
        ],

        // Recovery Code Card (Wajib jika pakai PIN / Password)
        if (secType != 'none') ...[
          const SizedBox(height: 20),
          Card(
            color: Colors.amber.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade400),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Text(
                        'PENTING: RECOVERY CODE',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Karena app ini 100% offline tanpa cloud, kode 16 karakter ini adalah SATU-SATUNYA cara mereset akun jika Anda lupa PIN/Password. Catat atau salin sekarang!',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SelectableText(
                          controller.recoveryCode.value,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: Colors.black87,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Salin Kode',
                          icon: const Icon(Icons.copy_rounded, color: Colors.black87),
                          onPressed: controller.copyRecoveryCode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: controller.hasRecordedRecoveryCode.value,
                    onChanged: (val) => controller.hasRecordedRecoveryCode.value = val ?? false,
                    title: const Text(
                      'Saya sudah mencatat dan menyimpan Recovery Code ini dengan aman.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final step = controller.currentStep.value;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (step > 0)
          OutlinedButton.icon(
            onPressed: controller.previousStep,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Kembali'),
          )
        else
          const SizedBox.shrink(),
        if (step < 2)
          FilledButton.icon(
            onPressed: controller.nextStep,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Lanjut'),
          )
        else
          FilledButton.icon(
            onPressed: controller.isLoading.value ? null : controller.finishSetup,
            icon: controller.isLoading.value
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('Selesai & Buka Aplikasi'),
          ),
      ],
    );
  }
}
