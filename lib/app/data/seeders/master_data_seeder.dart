import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../repositories/category_repository.dart';
import '../repositories/unit_repository.dart';

/// Seeder master data bawaan sistem (kategori & satuan awal, idempotent).
class MasterDataSeeder {
  MasterDataSeeder._();

  static const List<({String name, String symbol})> _defaultUnits = [
    (name: 'Pieces', symbol: 'pcs'),
    (name: 'Kilogram', symbol: 'kg'),
    (name: 'Gram', symbol: 'gram'),
    (name: 'Liter', symbol: 'liter'),
    (name: 'Dus', symbol: 'dus'),
    (name: 'Pack', symbol: 'pack'),
  ];

  /// Menyemai kategori 'Umum' dan satuan default ke database secara idempotent
  static Future<void> seed(
    CategoryRepository categoryRepo,
    UnitRepository unitRepo,
  ) async {
    // 1. Seed Kategori 'Umum' jika belum ada
    final existingCategory = await categoryRepo.getCategoryByName('Umum');
    if (existingCategory == null) {
      await categoryRepo.insertCategory(
        const CategoriesCompanion(
          name: Value('Umum'),
        ),
      );
    }

    // 2. Seed Satuan jika belum ada
    for (final unit in _defaultUnits) {
      final existingBySymbol = await unitRepo.getUnitBySymbol(unit.symbol);
      final existingByName = await unitRepo.getUnitByName(unit.name);

      if (existingBySymbol == null && existingByName == null) {
        await unitRepo.insertUnit(
          UnitsCompanion(
            name: Value(unit.name),
            symbol: Value(unit.symbol),
          ),
        );
      }
    }
  }
}

