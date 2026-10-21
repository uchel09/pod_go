import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;

import '../../data/local/app_database.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../audit/audit_actions.dart';
import '../permissions/permission_keys.dart';
import '../permissions/permission_service.dart';
import '../utils/app_exception.dart';
import '../utils/crypto_utils.dart';
import 'audit_service.dart';

class AuthService extends GetxService {
  static AuthService get to => Get.find<AuthService>();

  final StoreRepository _storeRepo;
  final UserRepository _userRepo;

  AuthService(this._storeRepo, this._userRepo);

  final Rxn<User> currentUser = Rxn<User>();
  final Rxn<Store> currentStore = Rxn<Store>();

  bool get isLoggedIn => currentUser.value != null;
  bool get hasStore => currentStore.value != null;
  bool get requireLogin => currentStore.value?.requireLogin ?? true;
  bool get isSoloMode => hasStore && currentStore.value?.mode == 'solo';

  Future<AuthService> init() async {
    await refreshState();
    return this;
  }

  /// Memuat ulang data toko & menangani autologin untuk mode Solo tanpa password
  Future<void> refreshState() async {
    final store = await _storeRepo.getStore();
    currentStore.value = store;

    if (store != null) {
      // Jika toko tidak membutuhkan login (mode Solo tanpa password), lakukan auto-login
      if (!store.requireLogin) {
        final users = await _userRepo.getAllUsers();
        if (users.isNotEmpty) {
          currentUser.value = users.first;
        }
      }
    }
  }

  /// Melakukan login dengan username dan password/PIN
  Future<void> login(String username, String secret) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || secret.isEmpty) {
      throw const AppException('Username dan password/PIN tidak boleh kosong.');
    }

    final user = await _userRepo.getUserByUsername(cleanUsername);
    if (user == null) {
      throw const AppException('Akun tidak ditemukan. Periksa kembali username Anda.');
    }

    // 1. Periksa status kunci akun (Lockout 5 menit)
    final now = DateTime.now();
    if (user.lockedUntil != null && now.isBefore(user.lockedUntil!)) {
      final remaining = user.lockedUntil!.difference(now);
      final minutes = remaining.inMinutes;
      final seconds = remaining.inSeconds % 60;
      throw AppException(
        'Akun terkunci karena terlalu banyak percobaan gagal. Coba lagi dalam $minutes menit $seconds detik.',
      );
    }

    // 2. Cocokkan kredensial (password atau PIN)
    bool isMatch = false;
    if (user.passwordHash != null) {
      isMatch = CryptoUtils.verifySecret(secret, user.passwordHash!);
    } else if (user.pinHash != null) {
      isMatch = CryptoUtils.verifySecret(secret, user.pinHash!);
    } else {
      // Jika user dibuat tanpa password
      isMatch = true;
    }

    if (!isMatch) {
      final newFailedAttempts = user.failedAttempts + 1;
      if (Get.isRegistered<AuditService>()) {
        AuditService.to.log(
          action: 'login.failed',
          entity: 'users',
          entityId: user.id,
          overrideUserId: user.id,
          detail: {'username': username, 'failedAttempts': newFailedAttempts},
        );
      }
      if (newFailedAttempts >= 5) {
        final lockoutTime = now.add(const Duration(minutes: 5));
        await _userRepo.updateUser(
          user.toCompanion(true).copyWith(
                failedAttempts: const Value(5),
                lockedUntil: Value(lockoutTime),
                updatedAt: Value(now),
              ),
        );
        throw const AppException(
          'Password/PIN salah 5 kali berturut-turut. Akun Anda dikunci selama 5 menit untuk keamanan.',
        );
      } else {
        await _userRepo.updateUser(
          user.toCompanion(true).copyWith(
                failedAttempts: Value(newFailedAttempts),
                updatedAt: Value(now),
              ),
        );
        final sisa = 5 - newFailedAttempts;
        throw AppException('Password/PIN salah. Sisa kesempatan: $sisa kali.');
      }
    }

    // 3. Login berhasil: Reset counter gagal dan catat lastLoginAt
    final updateCompanion = user.toCompanion(true).copyWith(
      failedAttempts: const Value(0),
      lockedUntil: const Value(null),
      lastLoginAt: Value(now),
      updatedAt: Value(now),
    );
    await _userRepo.updateUser(updateCompanion);

    currentUser.value = await _userRepo.getUserById(user.id);
    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'login.success',
        entity: 'users',
        entityId: user.id,
        overrideUserId: user.id,
      );
    }
  }

  /// Logout dari sesi saat ini
  void logout() {
    currentUser.value = null;
  }

  /// Reset password / PIN menggunakan Recovery Code 16 karakter
  Future<void> resetSecretWithRecoveryCode({
    required String username,
    required String recoveryCode,
    String? newPassword,
    String? newPin,
    required String newRecoveryCode,
  }) async {
    final cleanUsername = username.trim();
    final user = await _userRepo.getUserByUsername(cleanUsername);
    if (user == null) {
      throw const AppException('Akun pengguna tidak ditemukan.');
    }

    if (user.recoveryCodeHash == null || user.recoveryCodeHash!.isEmpty) {
      throw const AppException('Akun ini tidak memiliki Recovery Code yang terdaftar.');
    }

    // Verifikasi kode pemulihan
    final normalizedCode = CryptoUtils.normalizeCode(recoveryCode);
    final isMatch = CryptoUtils.verifySecret(normalizedCode, user.recoveryCodeHash!);
    if (!isMatch) {
      throw const AppException('Recovery Code tidak valid.');
    }

    // Hash secret baru & kode pemulihan baru
    final now = DateTime.now();
    final newRecoveryHash = CryptoUtils.hashSecret(CryptoUtils.normalizeCode(newRecoveryCode));
    String? newPassHash;
    String? newPinHash;

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      newPassHash = CryptoUtils.hashSecret(newPassword.trim());
    } else if (newPin != null && newPin.trim().isNotEmpty) {
      newPinHash = CryptoUtils.hashSecret(newPin.trim());
    }

    final updated = user.toCompanion(true).copyWith(
          passwordHash: Value(newPassHash),
          pinHash: Value(newPinHash),
          recoveryCodeHash: Value(newRecoveryHash),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
          mustChangePassword: const Value(false),
          updatedAt: Value(now),
        );

    await _userRepo.updateUser(updated);
    if (Get.isRegistered<AuditService>()) {
      AuditService.to.log(
        action: 'auth.recovery_reset',
        entity: 'users',
        entityId: user.id,
        overrideUserId: user.id,
      );
    }
  }

  /// Ganti password / PIN untuk user saat ini dengan verifikasi secret lama
  Future<void> changePasswordWithVerification({
    required String oldSecret,
    required String newSecret,
  }) async {
    final user = currentUser.value;
    if (user == null) {
      throw const AppException('Tidak ada sesi pengguna aktif.');
    }

    // 1. Verifikasi secret lama
    bool isMatch = false;
    if (user.passwordHash != null) {
      isMatch = CryptoUtils.verifySecret(oldSecret, user.passwordHash!);
    } else if (user.pinHash != null) {
      isMatch = CryptoUtils.verifySecret(oldSecret, user.pinHash!);
    } else {
      isMatch = true;
    }

    if (!isMatch) {
      throw const AppException('Password atau PIN lama tidak sesuai.');
    }

    final trimmed = newSecret.trim();
    if (trimmed.length < 4) {
      throw const AppException('Password atau PIN baru minimal 4 karakter/digit.');
    }

    // 2. Hash secret baru (tidak ada plain text yang disimpan)
    final now = DateTime.now();
    final isPin = int.tryParse(trimmed) != null && trimmed.length <= 6;
    final newPassHash = !isPin ? CryptoUtils.hashSecret(trimmed) : null;
    final newPinHash = isPin ? CryptoUtils.hashSecret(trimmed) : null;

    final updated = user.toCompanion(true).copyWith(
          passwordHash: Value(newPassHash),
          pinHash: Value(newPinHash),
          mustChangePassword: const Value(false),
          updatedAt: Value(now),
        );

    await _userRepo.updateUser(updated);
    currentUser.value = await _userRepo.getUserById(user.id);

    // 3. Catat audit
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.authPasswordChanged,
        entity: 'users',
        entityId: user.id,
        overrideUserId: user.id,
      );
    }
  }

  /// Memperbarui Recovery Code untuk user saat ini
  Future<void> rotateRecoveryCode({required String newRecoveryCode}) async {
    final user = currentUser.value;
    if (user == null) {
      throw const AppException('Tidak ada sesi pengguna aktif.');
    }

    final normalized = CryptoUtils.normalizeCode(newRecoveryCode);
    if (normalized.length != 16) {
      throw const AppException('Recovery code harus berjumlah 16 karakter.');
    }

    final newHash = CryptoUtils.hashSecret(normalized);
    final now = DateTime.now();

    final updated = user.toCompanion(true).copyWith(
          recoveryCodeHash: Value(newHash),
          updatedAt: Value(now),
        );

    await _userRepo.updateUser(updated);
    currentUser.value = await _userRepo.getUserById(user.id);

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.settingsUpdate,
        entity: 'users',
        entityId: user.id,
        detail: {'action': 'rotate_recovery_code'},
      );
    }
  }

  /// Mengaktifkan login wajib pada mode Solo (membuat secret dan recovery code baru)
  Future<void> activateSoloLogin({
    required String newSecret,
    required String newRecoveryCode,
  }) async {
    final store = currentStore.value;
    if (store == null || store.mode != 'solo') {
      throw const AppException('Pengaturan ini hanya tersedia pada toko Mode Solo.');
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.settingsManage)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk mengelola pengaturan toko.',
          code: 'FORBIDDEN',
        );
      }
    }

    final trimmed = newSecret.trim();
    if (trimmed.length < 4) {
      throw const AppException('Password atau PIN minimal 4 karakter/digit.');
    }

    final normalizedCode = CryptoUtils.normalizeCode(newRecoveryCode);
    if (normalizedCode.length != 16) {
      throw const AppException('Recovery code harus berjumlah 16 karakter.');
    }

    final isPin = int.tryParse(trimmed) != null && trimmed.length <= 6;
    final passHash = !isPin ? CryptoUtils.hashSecret(trimmed) : null;
    final pinHash = isPin ? CryptoUtils.hashSecret(trimmed) : null;
    final recoveryHash = CryptoUtils.hashSecret(normalizedCode);
    final now = DateTime.now();

    // 1. Update user
    final user = currentUser.value;
    if (user != null) {
      await _userRepo.updateUser(
        user.toCompanion(true).copyWith(
              passwordHash: Value(passHash),
              pinHash: Value(pinHash),
              recoveryCodeHash: Value(recoveryHash),
              mustChangePassword: const Value(false),
              updatedAt: Value(now),
            ),
      );
      currentUser.value = await _userRepo.getUserById(user.id);
    }

    // 2. Update store requireLogin = true
    await _storeRepo.updateStore(
      store.toCompanion(true).copyWith(
            requireLogin: const Value(true),
            updatedAt: Value(now),
          ),
    );
    await refreshState();

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.settingsUpdate,
        entity: 'stores',
        entityId: store.id,
        detail: {'key': 'require_login', 'enabled': true},
      );
    }
  }

  /// Menonaktifkan login wajib pada mode Solo (memerlukan verifikasi secret saat ini)
  Future<void> deactivateSoloLogin({required String currentSecret}) async {
    final store = currentStore.value;
    if (store == null || store.mode != 'solo') {
      throw const AppException('Pengaturan ini hanya tersedia pada toko Mode Solo.');
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.settingsManage)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk mengelola pengaturan toko.',
          code: 'FORBIDDEN',
        );
      }
    }

    final user = currentUser.value;
    if (user != null) {
      bool isMatch = false;
      if (user.passwordHash != null) {
        isMatch = CryptoUtils.verifySecret(currentSecret, user.passwordHash!);
      } else if (user.pinHash != null) {
        isMatch = CryptoUtils.verifySecret(currentSecret, user.pinHash!);
      } else {
        isMatch = true;
      }

      if (!isMatch) {
        throw const AppException(
          'Password atau PIN saat ini tidak sesuai. Login tidak dapat dinonaktifkan.',
        );
      }
    }

    final now = DateTime.now();
    await _storeRepo.updateStore(
      store.toCompanion(true).copyWith(
            requireLogin: const Value(false),
            updatedAt: Value(now),
          ),
    );
    await refreshState();

    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: AuditActions.settingsUpdate,
        entity: 'stores',
        entityId: store.id,
        detail: {'key': 'require_login', 'enabled': false},
      );
    }
  }

  /// Ganti password / PIN untuk user saat ini
  Future<void> changeCurrentPassword({
    String? newPassword,
    String? newPin,
  }) async {
    final user = currentUser.value;
    if (user == null) {
      throw const AppException('Tidak ada sesi pengguna aktif.');
    }

    final now = DateTime.now();
    String? newPassHash;
    String? newPinHash;

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      newPassHash = CryptoUtils.hashSecret(newPassword.trim());
    } else if (newPin != null && newPin.trim().isNotEmpty) {
      newPinHash = CryptoUtils.hashSecret(newPin.trim());
    }

    final updated = user.toCompanion(true).copyWith(
          passwordHash: Value(newPassHash),
          pinHash: Value(newPinHash),
          mustChangePassword: const Value(false),
          updatedAt: Value(now),
        );

    await _userRepo.updateUser(updated);
    currentUser.value = await _userRepo.getUserById(user.id);
    if (Get.isRegistered<AuditService>()) {
      await AuditService.to.log(
        action: 'auth.change_secret',
        entity: 'users',
        entityId: user.id,
        overrideUserId: user.id,
      );
    }
  }
}
