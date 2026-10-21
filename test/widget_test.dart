import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Value;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/theme/theme_service.dart';
import 'package:pos_me/app/core/utils/device_id_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'POS Me',
      packageName: 'com.posme',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'mock-device-id-12345',
      'app_theme_mode': 'light',
    });
    Get.reset();
    await Get.putAsync(() => ThemeService().init());
    await Get.putAsync(() => DeviceIdService().init());

    // Inisialisasi in-memory DB dan seed toko default Solo agar masuk ke Home
    db = AppDatabase(NativeDatabase.memory());
    Get.put<AppDatabase>(db, permanent: true);

    final storeRepo = StoreRepository(db.storeDao);
    final userRepo = UserRepository(db.userDao);
    final roleRepo = RoleRepository(db.roleDao);

    Get.put<StoreRepository>(storeRepo, permanent: true);
    Get.put<UserRepository>(userRepo, permanent: true);
    Get.put<RoleRepository>(roleRepo, permanent: true);

    await storeRepo.insertStore(
      const StoresCompanion(
        name: Value('Warung Berkah'),
        mode: Value('solo'),
        requireLogin: Value(false),
      ),
    );
    final roleId = await roleRepo.insertRole(
      const RolesCompanion(name: Value('Owner')),
    );
    await userRepo.insertUser(
      UsersCompanion(
        username: const Value('owner'),
        displayName: const Value('Pemilik Toko'),
        roleId: Value(roleId),
      ),
    );

    final authService = AuthService(storeRepo, userRepo);
    await authService.init();
    Get.put<AuthService>(authService, permanent: true);
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  testWidgets(
    'App renders HomeView with formatRupiah and AdaptiveScaffold on mobile (<600px)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const PosMeApp());
      await tester.pumpAndSettle();

      expect(find.text('Warung Berkah'), findsWidgets);
      expect(find.text('Rp 0'), findsWidgets);
      // On mobile (<600px), destinations are displayed via NavigationBar
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    },
  );

  testWidgets(
    'App renders AdaptiveScaffold on desktop (>=600px) with NavigationRail',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const PosMeApp());
      await tester.pumpAndSettle();

      expect(find.text('Warung Berkah'), findsWidgets);
      expect(find.text('Rp 0'), findsWidgets);
      // On desktop (>=600px), NavigationRail is used
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );
}
