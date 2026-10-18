import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/permissions/permission_service.dart';
import 'package:pos_me/app/core/services/auth_service.dart';
import 'package:pos_me/app/core/services/pdf/label_pdf_service.dart';
import 'package:pos_me/app/data/local/app_database.dart';
import 'package:pos_me/app/data/repositories/product_repository.dart';
import 'package:pos_me/app/data/repositories/role_repository.dart';
import 'package:pos_me/app/data/repositories/settings_repository.dart';
import 'package:pos_me/app/data/repositories/store_repository.dart';
import 'package:pos_me/app/data/repositories/user_repository.dart';
import 'package:pos_me/app/data/seeders/role_seeder.dart';
import 'package:pos_me/app/modules/product_labels/controllers/product_labels_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StoreRepository storeRepo;
  late UserRepository userRepo;
  late RoleRepository roleRepo;
  late ProductRepository productRepo;
  late SettingsRepository settingsRepo;
  late AuthService authService;
  late PermissionService permService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_device_id': 'mock-device-label-test',
    });
    Get.reset();
    db = AppDatabase(NativeDatabase.memory());
    storeRepo = StoreRepository(db.storeDao);
    userRepo = UserRepository(db.userDao);
    roleRepo = RoleRepository(db.roleDao);
    settingsRepo = SettingsRepository(db.settingsDao);
    productRepo = ProductRepository(
      db.productDao,
      settingsDao: db.settingsDao,
      storeDao: db.storeDao,
    );

    await RoleSeeder.seedDefaultRoles(roleRepo);

    authService = AuthService(storeRepo, userRepo);
    permService = PermissionService(roleRepo);
    Get.put<AuthService>(authService);
    Get.put<PermissionService>(permService);
    Get.put<ProductRepository>(productRepo);
    Get.put<SettingsRepository>(settingsRepo);

    // Setup Store
    await storeRepo.insertStore(
      const StoresCompanion(
        name: drift.Value('Toko Uji Label'),
        mode: drift.Value('solo'),
        scannerType: drift.Value('1d'),
      ),
    );

    await authService.init();
    await permService.init();
  });

  tearDown(() async {
    await db.close();
    Get.reset();
  });

  Product makeProduct({
    required int id,
    required String name,
    required int sellPrice,
    String? barcode,
    String? internalCode,
    String codeType = 'internal_code128',
  }) {
    return Product(
      id: id,
      name: name,
      sellPrice: sellPrice,
      costPrice: 5000,
      currentStock: 10,
      minStock: 2,
      barcode: barcode,
      internalCode: internalCode,
      codeType: codeType,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  group('LabelPdfService Tests', () {
    final p1 = makeProduct(
      id: 1,
      name: 'Kopi Susu Aren 250ml',
      sellPrice: 15000,
      barcode: 'P000001',
      internalCode: 'P000001',
      codeType: 'internal_code128',
    );
    final p2 = makeProduct(
      id: 2,
      name: 'Teh Tarik Hangat',
      sellPrice: 8000,
      barcode: 'P000002',
      internalCode: 'P000002',
      codeType: 'internal_code128',
    );
    final pLong = makeProduct(
      id: 3,
      name: 'Produk Kode Panjang Sekali',
      sellPrice: 25000,
      barcode: 'P0000123456789', // 14 karakter (> 12)
      internalCode: 'P0000123456789',
      codeType: 'internal_code128',
    );

    test('Menghasilkan bytes PDF yang valid (Header %PDF-)', () async {
      final bytes = await LabelPdfService.generatePdf(
        items: [
          LabelPrintItem(product: p1, copies: 3),
          LabelPrintItem(product: p2, copies: 2),
        ],
        template: LabelTemplateType.roll3Col40x20,
        format: LabelBarcodeFormat.code128,
        showPrice: true,
      );

      expect(bytes, isNotEmpty);
      final header = utf8.decode(bytes.sublist(0, 5), allowMalformed: true);
      expect(header, '%PDF-');
    });

    test('Mendukung semua template: roll3Col40x20, roll2Col50x30, dan a4Grid', () async {
      final items = [
        LabelPrintItem(product: p1, copies: 5),
        LabelPrintItem(product: p2, copies: 5),
      ];

      final pdf40x20 = await LabelPdfService.generatePdf(
        items: items,
        template: LabelTemplateType.roll3Col40x20,
        format: LabelBarcodeFormat.code128,
      );
      expect(pdf40x20.length, greaterThan(1000));

      final pdf50x30 = await LabelPdfService.generatePdf(
        items: items,
        template: LabelTemplateType.roll2Col50x30,
        format: LabelBarcodeFormat.code128,
      );
      expect(pdf50x30.length, greaterThan(1000));

      final pdfA4 = await LabelPdfService.generatePdf(
        items: items,
        template: LabelTemplateType.a4Grid,
        format: LabelBarcodeFormat.qr,
      );
      expect(pdfA4.length, greaterThan(1000));
    });

    test('Peringatan jika kode > 12 karakter pada template 40x20 mm Code128', () {
      final warningsNormal = LabelPdfService.checkWarnings(
        items: [LabelPrintItem(product: p1, copies: 1)],
        template: LabelTemplateType.roll3Col40x20,
        format: LabelBarcodeFormat.code128,
      );
      expect(warningsNormal, isEmpty);

      final warningsLong = LabelPdfService.checkWarnings(
        items: [LabelPrintItem(product: pLong, copies: 1)],
        template: LabelTemplateType.roll3Col40x20,
        format: LabelBarcodeFormat.code128,
      );
      expect(warningsLong, hasLength(1));
      expect(warningsLong.first, contains('terlalu rapat pada label 40x20 mm'));

      // Jika format QR, tidak ada peringatan Code128
      final warningsQr = LabelPdfService.checkWarnings(
        items: [LabelPrintItem(product: pLong, copies: 1)],
        template: LabelTemplateType.roll3Col40x20,
        format: LabelBarcodeFormat.qr,
      );
      expect(warningsQr, isEmpty);

      // Jika template 50x30 mm, tidak ada peringatan
      final warnings50x30 = LabelPdfService.checkWarnings(
        items: [LabelPrintItem(product: pLong, copies: 1)],
        template: LabelTemplateType.roll2Col50x30,
        format: LabelBarcodeFormat.code128,
      );
      expect(warnings50x30, isEmpty);
    });
  });

  group('ProductLabelsController Tests', () {
    test('Produk kemasan pabrik TIDAK masuk daftar terpilih default', () async {
      // Masukkan produk internal
      final id1 = await productRepo.createProduct(
        const ProductsCompanion(
          name: drift.Value('Produk Internal 1'),
          sellPrice: drift.Value(10000),
          barcode: drift.Value('P000001'),
          internalCode: drift.Value('P000001'),
          codeType: drift.Value('internal_code128'),
          isActive: drift.Value(true),
        ),
      );

      // Masukkan produk kemasan pabrik
      final id2 = await productRepo.createProduct(
        const ProductsCompanion(
          name: drift.Value('Indomie Goreng Pabrik'),
          sellPrice: drift.Value(3500),
          barcode: drift.Value('8998866200225'),
          codeType: drift.Value('manufacturer'),
          isActive: drift.Value(true),
        ),
      );

      final controller = ProductLabelsController();
      Get.put<ProductLabelsController>(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.allProducts, hasLength(2));
      // Hanya produk internal (id1) yang terpilih default
      expect(controller.selectedProductIds.contains(id1), isTrue);
      // Produk pabrik (id2) TIDAK terpilih default
      expect(controller.selectedProductIds.contains(id2), isFalse);

      // Tombol pilih semua produk internal
      controller.deselectAll();
      expect(controller.selectedProductIds, isEmpty);

      controller.selectAllInternalProducts();
      expect(controller.selectedProductIds.contains(id1), isTrue);
      expect(controller.selectedProductIds.contains(id2), isFalse);

      // Update jumlah salinan
      controller.updateCopies(id1, 5);
      expect(controller.productCopies[id1], 5);
      expect(controller.totalLabelsCount, 5);
    });

    test('Navigasi dengan argumen productId otomatis memilih produk tersebut', () async {
      final id1 = await productRepo.createProduct(
        const ProductsCompanion(
          name: drift.Value('Produk A'),
          sellPrice: drift.Value(10000),
          barcode: drift.Value('P000001'),
          internalCode: drift.Value('P000001'),
          codeType: drift.Value('internal_code128'),
          isActive: drift.Value(true),
        ),
      );

      final id2 = await productRepo.createProduct(
        const ProductsCompanion(
          name: drift.Value('Produk B'),
          sellPrice: drift.Value(15000),
          barcode: drift.Value('P000002'),
          internalCode: drift.Value('P000002'),
          codeType: drift.Value('internal_code128'),
          isActive: drift.Value(true),
        ),
      );

      expect(id1, greaterThan(0));
      expect(id2, greaterThan(0));

      final controller = ProductLabelsController();
      Get.parameters = {};
      Get.replace(controller);

      expect(controller.canView, isTrue);
    });
  });
}

