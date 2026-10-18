import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/utils/app_exception.dart';
import 'package:pos_me/app/core/utils/crypto_utils.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';

void main() {
  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late AuthService authService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    authService = AuthService(storeRepo, userRepo);
  });

  tearDown(() async {
    await db.close();
  });

  test('Mode Solo tanpa password: autoLogin aktif dan requireLogin false', () async {
    // 1. Setup toko Solo tanpa login
    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Warung Berkah'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );

    final roleId = await roleRepo.insertRole(
      const RolesCompanion(
        name: Value('Owner'),
        isSystem: Value(true),
      ),
    );

    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Pemilik Warung'),
        roleId: Value(roleId),
      ),
    );

    // 2. Inisialisasi AuthService
    await authService.init();

    expect(authService.hasStore, isTrue);
    expect(authService.requireLogin, isFalse);
    expect(authService.isLoggedIn, isTrue);
    expect(authService.currentUser.value?.username, 'owner');
  });

  test('Mode Login: Verifikasi password bcrypt & gagal 5x mengunci akun 5 menit', () async {
    final passwordHash = CryptoUtils.hashSecret('rahasia123');

    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Toko Maju'),
        mode: Value('solo'),
        requireLogin: Value(true),
      ),
    );

    final roleId = await roleRepo.insertRole(
      const RolesCompanion(name: Value('Owner')),
    );

    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('kasir1'),
        displayName: const Value('Kasir Satu'),
        passwordHash: Value(passwordHash),
        roleId: Value(roleId),
      ),
    );

    await authService.init();
    expect(authService.isLoggedIn, isFalse);

    // Salah password 4 kali berturut-turut
    for (int i = 1; i <= 4; i++) {
      await expectLater(
        authService.login('kasir1', 'passwordsalah'),
        throwsA(isA<AppException>()),
      );
      final u = await userRepo.getUserByUsername('kasir1');
      expect(u?.failedAttempts, i);
      expect(u?.lockedUntil, isNull);
    }

    // Percobaan ke-5 salah -> harus mengunci akun selama 5 menit
    await expectLater(
      authService.login('kasir1', 'passwordsalah'),
      throwsA(isA<AppException>()),
    );

    final lockedUser = await userRepo.getUserByUsername('kasir1');
    expect(lockedUser?.failedAttempts, 5);
    expect(lockedUser?.lockedUntil, isNotNull);
    expect(lockedUser!.lockedUntil!.isAfter(DateTime.now()), isTrue);

    // Percobaan login saat akun terkunci harus melempar error terkunci
    await expectLater(
      authService.login('kasir1', 'rahasia123'),
      throwsA(isA<AppException>()),
    );

    // Login berhasil setelah unlock dan password benar
    final unlockCompanion = lockedUser.toCompanion(true).copyWith(
      lockedUntil: const Value(null),
      failedAttempts: const Value(0),
    );
    await userRepo.updateUser(unlockCompanion);

    await authService.login('kasir1', 'rahasia123');
    expect(authService.isLoggedIn, isTrue);
    expect(authService.currentUser.value?.username, 'kasir1');
  });

  test('Recovery Code 16 karakter berhasil mereset password akun owner', () async {
    const rawRecoveryCode = 'ABCD-EFGH-JKLM-NPQR';
    final normalizedRecovery = CryptoUtils.normalizeCode(rawRecoveryCode);
    final recoveryHash = CryptoUtils.hashSecret(normalizedRecovery);

    final roleId = await roleRepo.insertRole(
      const RolesCompanion(name: Value('Owner')),
    );

    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner_lupa'),
        displayName: const Value('Owner Lupa'),
        passwordHash: Value(CryptoUtils.hashSecret('lama123')),
        recoveryCodeHash: Value(recoveryHash),
        roleId: Value(roleId),
      ),
    );

    // Coba recovery dengan kode salah -> gagal
    await expectLater(
      authService.resetSecretWithRecoveryCode(
        username: 'owner_lupa',
        recoveryCode: 'SALAH-KODE-1234-5678',
        newPassword: 'baru456Password',
        newRecoveryCode: 'NEW1-NEW2-NEW3-NEW4',
      ),
      throwsA(isA<AppException>()),
    );

    // Recovery dengan kode benar -> sukses
    await authService.resetSecretWithRecoveryCode(
      username: 'owner_lupa',
      recoveryCode: rawRecoveryCode,
      newPassword: 'baru456Password',
      newRecoveryCode: 'NEW1-NEW2-NEW3-NEW4',
    );

    final updated = await userRepo.getUserByUsername('owner_lupa');
    expect(updated, isNotNull);
    // Verifikasi password baru dapat digunakan untuk login
    final isNewPassValid = CryptoUtils.verifySecret('baru456Password', updated!.passwordHash!);
    expect(isNewPassValid, isTrue);
  });
}
