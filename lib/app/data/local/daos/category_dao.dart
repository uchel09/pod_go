import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/categories.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<Category>> getAllCategories() => select(categories).get();

  Stream<List<Category>> watchAllCategories() => select(categories).watch();

  Future<Category?> getCategoryById(int id) =>
      (select(categories)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Category?> getCategoryByName(String name) =>
      (select(categories)..where((t) => t.name.lower().equals(name.toLowerCase()))).getSingleOrNull();

  Future<int> insertCategory(CategoriesCompanion category) =>
      into(categories).insert(category);

  Future<bool> updateCategory(CategoriesCompanion category) =>
      update(categories).replace(category);

  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((t) => t.id.equals(id))).go();
}

