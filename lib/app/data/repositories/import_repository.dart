import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/number_parser.dart';
import '../local/app_database.dart';
import '../local/daos/category_dao.dart';
import '../local/daos/product_dao.dart';
import '../local/daos/settings_dao.dart';
import '../local/daos/supplier_dao.dart';
import '../local/daos/unit_dao.dart';
import '../models/import_models.dart';
import 'product_repository.dart';
import 'stock_repository.dart';

class ImportRepository {
  final AppDatabase _db;
  final ProductDao _productDao;
  final CategoryDao _categoryDao;
  final UnitDao _unitDao;
  final SupplierDao _supplierDao;
  final SettingsDao _settingsDao;
  final StockRepository _stockRepo;
  final ProductRepository _productRepo;

  ImportRepository({
    required AppDatabase db,
    required ProductDao productDao,
    required CategoryDao categoryDao,
    required UnitDao unitDao,
    required SupplierDao supplierDao,
    required SettingsDao settingsDao,
    required StockRepository stockRepo,
    required ProductRepository productRepo,
  })  : _db = db,
        _productDao = productDao,
        _categoryDao = categoryDao,
        _unitDao = unitDao,
        _supplierDao = supplierDao,
        _settingsDao = settingsDao,
        _stockRepo = stockRepo,
        _productRepo = productRepo;

  /// Memverifikasi hak akses dan lisensi pengguna (Dual-layer gating)
  void _assertAccess() {
    if (Get.isRegistered<FeatureGate>()) {
      if (!FeatureGate.to.isEnabled(Feature.importExport)) {
        throw const AppException(
          'Fitur Import Data memerlukan lisensi Semi Premium ke atas.',
          code: 'FEATURE_LOCKED',
        );
      }
    }

    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.importManage)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk mengimpor data.',
          code: 'FORBIDDEN',
        );
      }
    }
  }

  // =========================================================================
  // TAHAP 1 & 2: VALIDASI & PREVIEW DATA BARIS
  // =========================================================================

  /// Memvalidasi baris-baris produk dan menghasilkan daftar [ImportPreviewRow]
  Future<List<ImportPreviewRow>> validateProductRows({
    required List<Map<String, dynamic>> rows,
    required ImportOptions options,
  }) async {
    _assertAccess();

    final previewRows = <ImportPreviewRow>[];
    final seenBarcodesInFile = <String>{};
    final seenSkusInFile = <String>{};

    for (int i = 0; i < rows.length; i++) {
      final raw = rows[i];
      final errors = <String>[];
      final warnings = <String>[];
      final parsed = <String, dynamic>{};

      final name = (raw['nama'] ?? '').toString().trim();
      if (name.isEmpty) {
        errors.add('Nama produk tidak boleh kosong');
      } else {
        parsed['name'] = name;
      }

      final sku = (raw['sku'] ?? '').toString().trim();
      if (sku.isNotEmpty) {
        parsed['sku'] = sku;
        if (seenSkusInFile.contains(sku.toLowerCase())) {
          errors.add('SKU "$sku" terduplikasi dalam berkas');
        } else {
          seenSkusInFile.add(sku.toLowerCase());
        }
      }

      final barcode = (raw['barcode'] ?? '').toString().trim();
      if (barcode.isNotEmpty) {
        parsed['barcode'] = barcode;
        if (seenBarcodesInFile.contains(barcode.toLowerCase())) {
          errors.add('Barcode "$barcode" terduplikasi dalam berkas');
        } else {
          seenBarcodesInFile.add(barcode.toLowerCase());
        }
      }

      // Harga Jual (Wajib & Non-negatif)
      final rawSell = raw['harga_jual'];
      final sellPrice = NumberParser.parseRupiah(rawSell);
      if (sellPrice == null) {
        errors.add('Harga jual wajib diisi angka valid');
      } else if (sellPrice < 0) {
        errors.add('Harga jual tidak boleh bernilai negatif');
      } else {
        parsed['sellPrice'] = sellPrice;
      }

      // Harga Beli (Opsional, Default 0, Non-negatif)
      final rawCost = raw['harga_beli'];
      final costPrice = rawCost != null && rawCost.toString().trim().isNotEmpty
          ? NumberParser.parseRupiah(rawCost)
          : 0;
      if (costPrice == null || costPrice < 0) {
        errors.add('Harga beli tidak valid atau bernilai negatif');
      } else {
        parsed['costPrice'] = costPrice;
      }

      // Stok Awal (Opsional, Default 0, Non-negatif)
      final rawStock = raw['stok_awal'];
      final initialStock = rawStock != null && rawStock.toString().trim().isNotEmpty
          ? NumberParser.parseInt(rawStock)
          : 0;
      if (initialStock == null || initialStock < 0) {
        errors.add('Stok awal tidak valid atau bernilai negatif');
      } else {
        parsed['initialStock'] = initialStock;
      }

      // Stok Minimum (Opsional, Default 0, Non-negatif)
      final rawMinStock = raw['stok_minimum'];
      final minStock = rawMinStock != null && rawMinStock.toString().trim().isNotEmpty
          ? NumberParser.parseInt(rawMinStock)
          : 0;
      if (minStock == null || minStock < 0) {
        errors.add('Stok minimum tidak valid atau bernilai negatif');
      } else {
        parsed['minStock'] = minStock;
      }

      // Kategori
      final catName = (raw['kategori'] ?? '').toString().trim();
      if (catName.isNotEmpty) {
        parsed['categoryName'] = catName;
        final cat = await _categoryDao.getCategoryByName(catName);
        if (cat != null) {
          parsed['categoryId'] = cat.id;
        } else if (!options.autoCreateCategory) {
          errors.add('Kategori "$catName" tidak terdaftar di sistem');
        } else {
          warnings.add('Kategori "$catName" akan dibuat otomatis');
        }
      }

      // Satuan
      final unitName = (raw['satuan'] ?? '').toString().trim();
      if (unitName.isNotEmpty) {
        parsed['unitName'] = unitName;
        var unit = await _unitDao.getUnitByName(unitName);
        unit ??= await _unitDao.getUnitBySymbol(unitName);
        if (unit != null) {
          parsed['unitId'] = unit.id;
        } else if (!options.autoCreateUnit) {
          errors.add('Satuan "$unitName" tidak terdaftar di sistem');
        } else {
          warnings.add('Satuan "$unitName" akan dibuat otomatis');
        }
      }

      // Pengecekan Keberadaan di Database (Barcode / SKU)
      Product? existingProduct;
      if (barcode.isNotEmpty) {
        existingProduct = await _productDao.getProductByBarcode(barcode);
      }
      if (existingProduct == null && sku.isNotEmpty) {
        existingProduct = await _productDao.getProductBySku(sku);
      }

      bool isUpdate = false;
      int? existingId;

      if (existingProduct != null) {
        existingId = existingProduct.id;
        if (options.mode == ImportMode.insertOnly) {
          errors.add('Produk dengan Barcode/SKU sudah ada di database (#${existingProduct.id} ${existingProduct.name})');
        } else {
          isUpdate = true;
          parsed['existingProduct'] = existingProduct;
          if (options.correctStock && initialStock != null && initialStock != existingProduct.currentStock) {
            warnings.add('Stok akan disesuaikan: ${existingProduct.currentStock} -> $initialStock');
          }
        }
      }

      previewRows.add(
        ImportPreviewRow(
          rowIndex: i + 1,
          fileLineNumber: i + 2,
          rawValues: raw,
          parsedValues: parsed,
          isValid: errors.isEmpty,
          isUpdate: isUpdate,
          existingEntityId: existingId,
          errors: errors,
          warnings: warnings,
        ),
      );
    }

    return previewRows;
  }

  /// Memvalidasi baris-baris kategori dan menghasilkan daftar [ImportPreviewRow]
  Future<List<ImportPreviewRow>> validateCategoryRows({
    required List<Map<String, dynamic>> rows,
    required ImportOptions options,
  }) async {
    _assertAccess();

    final previewRows = <ImportPreviewRow>[];
    final seenNamesInFile = <String>{};

    for (int i = 0; i < rows.length; i++) {
      final raw = rows[i];
      final errors = <String>[];
      final warnings = <String>[];
      final parsed = <String, dynamic>{};

      final name = (raw['nama'] ?? '').toString().trim();
      if (name.isEmpty) {
        errors.add('Nama kategori tidak boleh kosong');
      } else {
        parsed['name'] = name;
        if (seenNamesInFile.contains(name.toLowerCase())) {
          errors.add('Kategori "$name" terduplikasi dalam berkas');
        } else {
          seenNamesInFile.add(name.toLowerCase());
        }
      }

      bool isUpdate = false;
      int? existingId;

      if (name.isNotEmpty) {
        final existing = await _categoryDao.getCategoryByName(name);
        if (existing != null) {
          existingId = existing.id;
          if (options.mode == ImportMode.insertOnly) {
            errors.add('Kategori "$name" sudah terdaftar di database');
          } else {
            isUpdate = true;
            warnings.add('Kategori sudah ada, data akan dipertahankan');
          }
        }
      }

      previewRows.add(
        ImportPreviewRow(
          rowIndex: i + 1,
          fileLineNumber: i + 2,
          rawValues: raw,
          parsedValues: parsed,
          isValid: errors.isEmpty,
          isUpdate: isUpdate,
          existingEntityId: existingId,
          errors: errors,
          warnings: warnings,
        ),
      );
    }

    return previewRows;
  }

  /// Memvalidasi baris-baris supplier dan menghasilkan daftar [ImportPreviewRow]
  Future<List<ImportPreviewRow>> validateSupplierRows({
    required List<Map<String, dynamic>> rows,
    required ImportOptions options,
  }) async {
    _assertAccess();

    final previewRows = <ImportPreviewRow>[];
    final seenNamesInFile = <String>{};

    for (int i = 0; i < rows.length; i++) {
      final raw = rows[i];
      final errors = <String>[];
      final warnings = <String>[];
      final parsed = <String, dynamic>{};

      final name = (raw['nama'] ?? '').toString().trim();
      if (name.isEmpty) {
        errors.add('Nama supplier tidak boleh kosong');
      } else {
        parsed['name'] = name;
        if (seenNamesInFile.contains(name.toLowerCase())) {
          errors.add('Supplier "$name" terduplikasi dalam berkas');
        } else {
          seenNamesInFile.add(name.toLowerCase());
        }
      }

      final phone = (raw['telepon'] ?? '').toString().trim();
      parsed['phone'] = phone;

      final address = (raw['alamat'] ?? '').toString().trim();
      parsed['address'] = address;

      bool isUpdate = false;
      int? existingId;

      if (name.isNotEmpty) {
        final existing = await _supplierDao.getSupplierByName(name);
        if (existing != null) {
          existingId = existing.id;
          if (options.mode == ImportMode.insertOnly) {
            errors.add('Supplier "$name" sudah terdaftar di database');
          } else {
            isUpdate = true;
            warnings.add('Supplier sudah ada, telepon & alamat akan diperbarui');
          }
        }
      }

      previewRows.add(
        ImportPreviewRow(
          rowIndex: i + 1,
          fileLineNumber: i + 2,
          rawValues: raw,
          parsedValues: parsed,
          isValid: errors.isEmpty,
          isUpdate: isUpdate,
          existingEntityId: existingId,
          errors: errors,
          warnings: warnings,
        ),
      );
    }

    return previewRows;
  }

  // =========================================================================
  // TAHAP 3: EKSEKUSI IMPOR PER BATCH (~200 BARIS)
  // =========================================================================

  /// Menjalankan impor produk secara atomik per batch
  Future<ImportSummary> executeImportProducts({
    required List<ImportPreviewRow> previewRows,
    required ImportOptions options,
    required String fileName,
    void Function(int processed, int total, String status)? onProgress,
  }) async {
    _assertAccess();

    final currentUser = AuthService.to.currentUser.value;
    final userId = currentUser?.id;

    // Filter baris yang akan diproses
    final validRows = <ImportPreviewRow>[];
    final errorMessages = <String>[];
    int skippedCount = 0;

    for (final row in previewRows) {
      if (row.isValid) {
        validRows.add(row);
      } else {
        if (!options.skipErrorRows) {
          throw AppException(
            'Impor dibatalkan: Ditemukan kesalahan pada baris ${row.fileLineNumber} (${row.errorSummary}).',
          );
        }
        skippedCount++;
        errorMessages.add('Baris ${row.fileLineNumber}: ${row.errorSummary}');
      }
    }

    if (validRows.isEmpty) {
      return ImportSummary(
        totalRows: previewRows.length,
        successCount: 0,
        skippedCount: skippedCount,
        failedCount: 0,
        errorMessages: errorMessages,
      );
    }

    // Cache kategori dan satuan yang baru dibuat selama sesi impor
    final categoryCache = <String, int>{};
    final unitCache = <String, int>{};

    int createdCount = 0;
    int updatedCount = 0;
    int failedCount = 0;

    const batchSize = 200;
    final totalValid = validRows.length;

    for (int batchStart = 0; batchStart < totalValid; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < totalValid) ? batchStart + batchSize : totalValid;
      final currentBatch = validRows.sublist(batchStart, batchEnd);

      onProgress?.call(
        batchStart,
        totalValid,
        'Memproses batch ${batchStart + 1} - $batchEnd dari $totalValid baris...',
      );

      // Eksekusi tiap batch 200 baris dalam satu transaksi database
      await _db.transaction(() async {
        for (final row in currentBatch) {
          try {
            final parsed = row.parsedValues;
            final name = parsed['name'] as String;
            final sku = parsed['sku'] as String?;
            final barcode = parsed['barcode'] as String?;
            final sellPrice = parsed['sellPrice'] as int;
            final costPrice = (parsed['costPrice'] as int?) ?? 0;
            final initialStock = (parsed['initialStock'] as int?) ?? 0;
            final minStock = (parsed['minStock'] as int?) ?? 0;

            // Resolusi Kategori
            int? categoryId = parsed['categoryId'] as int?;
            final catName = parsed['categoryName'] as String?;
            if (categoryId == null && catName != null && catName.isNotEmpty) {
              if (categoryCache.containsKey(catName.toLowerCase())) {
                categoryId = categoryCache[catName.toLowerCase()];
              } else {
                final cat = await _categoryDao.getCategoryByName(catName);
                if (cat != null) {
                  categoryId = cat.id;
                  categoryCache[catName.toLowerCase()] = cat.id;
                } else if (options.autoCreateCategory) {
                  categoryId = await _categoryDao.insertCategory(
                    CategoriesCompanion(
                      name: Value(catName),
                      createdAt: Value(DateTime.now()),
                      updatedAt: Value(DateTime.now()),
                    ),
                  );
                  categoryCache[catName.toLowerCase()] = categoryId;
                }
              }
            }

            // Resolusi Satuan
            int? unitId = parsed['unitId'] as int?;
            final unitName = parsed['unitName'] as String?;
            if (unitId == null && unitName != null && unitName.isNotEmpty) {
              if (unitCache.containsKey(unitName.toLowerCase())) {
                unitId = unitCache[unitName.toLowerCase()];
              } else {
                var unit = await _unitDao.getUnitByName(unitName);
                unit ??= await _unitDao.getUnitBySymbol(unitName);
                if (unit != null) {
                  unitId = unit.id;
                  unitCache[unitName.toLowerCase()] = unit.id;
                } else if (options.autoCreateUnit) {
                  unitId = await _unitDao.insertUnit(
                    UnitsCompanion(
                      name: Value(unitName),
                      symbol: Value(unitName.toLowerCase()),
                      createdAt: Value(DateTime.now()),
                      updatedAt: Value(DateTime.now()),
                    ),
                  );
                  unitCache[unitName.toLowerCase()] = unitId;
                }
              }
            }

            if (row.isUpdate && row.existingEntityId != null) {
              // MODE PERBARUI (UPSERT)
              final existingProduct = (parsed['existingProduct'] as Product?) ??
                  await _productDao.getProductById(row.existingEntityId!);

              if (existingProduct != null) {
                await _productDao.updateProduct(
                  ProductsCompanion(
                    id: Value(existingProduct.id),
                    name: Value(name),
                    sku: Value(sku ?? existingProduct.sku),
                    barcode: Value(barcode ?? existingProduct.barcode),
                    internalCode: Value(existingProduct.internalCode),
                    codeType: Value(existingProduct.codeType),
                    categoryId: Value(categoryId ?? existingProduct.categoryId),
                    unitId: Value(unitId ?? existingProduct.unitId),
                    costPrice: Value(costPrice),
                    sellPrice: Value(sellPrice),
                    minStock: Value(minStock),
                    currentStock: Value(existingProduct.currentStock),
                    isActive: Value(existingProduct.isActive),
                    updatedAt: Value(DateTime.now()),
                  ),
                );

                // Sinkronisasi counter internalCode bila barcode berupa format Pxxxxxx
                await _syncInternalProductCounter(existingProduct.internalCode ?? barcode);

                // Koreksi stok bila opsi aktif
                if (options.correctStock) {
                  final diff = initialStock - existingProduct.currentStock;
                  if (diff != 0) {
                    await _stockRepo.applyMovement(
                      productId: existingProduct.id,
                      type: 'adjustment',
                      qtyChange: diff,
                      note: 'Koreksi stok impor: $fileName',
                      createdBy: userId,
                    );
                  }
                }

                updatedCount++;
              }
            } else {
              // MODE TAMBAH BARU (INSERT)
              // Pengecekan batas kuota produk tier aktif
              final limit = FeatureGate.to.productLimit;
              if (limit != null) {
                final activeCount = await _productDao.countActiveProducts();
                if (activeCount >= limit) {
                  throw LimitReachedException(
                    'Batas maksimal $limit produk aktif tier Anda telah tercapai saat impor berkas.',
                    limit: limit,
                  );
                }
              }

              // Buat atau tentukan internalCode
              String internalCode;
              String codeType;

              final internalCodeMatch = RegExp(r'^P(\d+)$', caseSensitive: false);
              if (barcode != null && internalCodeMatch.hasMatch(barcode)) {
                internalCode = barcode.toUpperCase();
                codeType = 'internal_code128';
                await _syncInternalProductCounter(internalCode);
              } else {
                final generated = await _productRepo.generateInternalCode();
                internalCode = generated['code']!;
                codeType = barcode != null && barcode.isNotEmpty ? 'manufacturer' : generated['codeType']!;
              }

              final newProductId = await _productDao.insertProduct(
                ProductsCompanion(
                  name: Value(name),
                  sku: Value(sku),
                  barcode: Value(barcode),
                  internalCode: Value(internalCode),
                  codeType: Value(codeType),
                  categoryId: Value(categoryId),
                  unitId: Value(unitId),
                  costPrice: Value(costPrice),
                  sellPrice: Value(sellPrice),
                  minStock: Value(minStock),
                  currentStock: const Value(0),
                  isActive: const Value(true),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              );

              // Catat stok awal lewat stock movement adjustment jika > 0
              if (initialStock > 0) {
                await _stockRepo.applyMovement(
                  productId: newProductId,
                  type: 'adjustment',
                  qtyChange: initialStock,
                  note: 'Stok awal impor: $fileName',
                  createdBy: userId,
                );
              }

              createdCount++;
            }
          } catch (e) {
            failedCount++;
            errorMessages.add('Baris ${row.fileLineNumber}: Gagal diproses (${e.toString()})');
            if (!options.skipErrorRows) {
              rethrow;
            }
          }
        }
      });
    }

    final successCount = createdCount + updatedCount;

    // Catat Jejak Audit
    await AuditService.to.log(
      action: AuditActions.importRun,
      entity: 'product',
      detail: {
        'type': 'product',
        'count': successCount,
        'created': createdCount,
        'updated': updatedCount,
        'skipped': skippedCount,
        'failed': failedCount,
        'fileName': fileName,
      },
    );

    return ImportSummary(
      totalRows: previewRows.length,
      successCount: successCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      errorMessages: errorMessages,
    );
  }

  /// Menjalankan impor kategori secara atomik per batch
  Future<ImportSummary> executeImportCategories({
    required List<ImportPreviewRow> previewRows,
    required ImportOptions options,
    required String fileName,
    void Function(int processed, int total, String status)? onProgress,
  }) async {
    _assertAccess();

    final validRows = <ImportPreviewRow>[];
    final errorMessages = <String>[];
    int skippedCount = 0;

    for (final row in previewRows) {
      if (row.isValid) {
        validRows.add(row);
      } else {
        if (!options.skipErrorRows) {
          throw AppException('Impor dibatalkan: Kesalahan pada baris ${row.fileLineNumber}.');
        }
        skippedCount++;
        errorMessages.add('Baris ${row.fileLineNumber}: ${row.errorSummary}');
      }
    }

    int createdCount = 0;
    int updatedCount = 0;
    int failedCount = 0;

    const batchSize = 200;
    final totalValid = validRows.length;

    for (int batchStart = 0; batchStart < totalValid; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < totalValid) ? batchStart + batchSize : totalValid;
      final currentBatch = validRows.sublist(batchStart, batchEnd);

      await _db.transaction(() async {
        for (final row in currentBatch) {
          try {
            final name = row.parsedValues['name'] as String;
            final existing = await _categoryDao.getCategoryByName(name);

            if (existing != null) {
              if (options.mode == ImportMode.upsert) {
                updatedCount++;
              }
            } else {
              await _categoryDao.insertCategory(
                CategoriesCompanion(
                  name: Value(name),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              );
              createdCount++;
            }
          } catch (e) {
            failedCount++;
            errorMessages.add('Baris ${row.fileLineNumber}: Gagal disimpan ($e)');
          }
        }
      });
    }

    final successCount = createdCount + updatedCount;

    await AuditService.to.log(
      action: AuditActions.importRun,
      entity: 'category',
      detail: {
        'type': 'category',
        'count': successCount,
        'created': createdCount,
        'updated': updatedCount,
        'skipped': skippedCount,
        'failed': failedCount,
        'fileName': fileName,
      },
    );

    return ImportSummary(
      totalRows: previewRows.length,
      successCount: successCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      errorMessages: errorMessages,
    );
  }

  /// Menjalankan impor supplier secara atomik per batch
  Future<ImportSummary> executeImportSuppliers({
    required List<ImportPreviewRow> previewRows,
    required ImportOptions options,
    required String fileName,
    void Function(int processed, int total, String status)? onProgress,
  }) async {
    _assertAccess();

    final validRows = <ImportPreviewRow>[];
    final errorMessages = <String>[];
    int skippedCount = 0;

    for (final row in previewRows) {
      if (row.isValid) {
        validRows.add(row);
      } else {
        if (!options.skipErrorRows) {
          throw AppException('Impor dibatalkan: Kesalahan pada baris ${row.fileLineNumber}.');
        }
        skippedCount++;
        errorMessages.add('Baris ${row.fileLineNumber}: ${row.errorSummary}');
      }
    }

    int createdCount = 0;
    int updatedCount = 0;
    int failedCount = 0;

    const batchSize = 200;
    final totalValid = validRows.length;

    for (int batchStart = 0; batchStart < totalValid; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < totalValid) ? batchStart + batchSize : totalValid;
      final currentBatch = validRows.sublist(batchStart, batchEnd);

      await _db.transaction(() async {
        for (final row in currentBatch) {
          try {
            final name = row.parsedValues['name'] as String;
            final phone = row.parsedValues['phone'] as String?;
            final address = row.parsedValues['address'] as String?;

            final existing = await _supplierDao.getSupplierByName(name);
            if (existing != null) {
              if (options.mode == ImportMode.upsert) {
                await _supplierDao.updateSupplier(
                  SuppliersCompanion(
                    id: Value(existing.id),
                    name: Value(name),
                    phone: Value(phone?.isNotEmpty == true ? phone : existing.phone),
                    address: Value(address?.isNotEmpty == true ? address : existing.address),
                    updatedAt: Value(DateTime.now()),
                  ),
                );
                updatedCount++;
              }
            } else {
              await _supplierDao.insertSupplier(
                SuppliersCompanion(
                  name: Value(name),
                  phone: Value(phone),
                  address: Value(address),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              );
              createdCount++;
            }
          } catch (e) {
            failedCount++;
            errorMessages.add('Baris ${row.fileLineNumber}: Gagal disimpan ($e)');
          }
        }
      });
    }

    final successCount = createdCount + updatedCount;

    await AuditService.to.log(
      action: AuditActions.importRun,
      entity: 'supplier',
      detail: {
        'type': 'supplier',
        'count': successCount,
        'created': createdCount,
        'updated': updatedCount,
        'skipped': skippedCount,
        'failed': failedCount,
        'fileName': fileName,
      },
    );

    return ImportSummary(
      totalRows: previewRows.length,
      successCount: successCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      errorMessages: errorMessages,
    );
  }

  /// Menyelaraskan counter internal code agar tidak bentrok dengan kode baru yang diimpor
  Future<void> _syncInternalProductCounter(String? code) async {
    if (code == null) return;
    final match = RegExp(r'^P(\d+)$', caseSensitive: false).firstMatch(code.trim());
    if (match != null) {
      final codeNum = int.tryParse(match.group(1) ?? '');
      if (codeNum != null) {
        const key = 'internal_product_counter';
        final currentStr = await _settingsDao.getSetting(key);
        final currentVal = currentStr != null ? (int.tryParse(currentStr) ?? 1) : 1;
        if (codeNum >= currentVal) {
          await _settingsDao.setSetting(key, (codeNum + 1).toString());
        }
      }
    }
  }
}

