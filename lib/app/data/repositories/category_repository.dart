import '../local/app_database.dart';
import '../local/daos/category_dao.dart';

class CategoryRepository {
  final CategoryDao _dao;

  CategoryRepository(this._dao);

  Future<List<Category>> getAllCategories() => _dao.getAllCategories();
  Stream<List<Category>> watchAllCategories() => _dao.watchAllCategories();
  Future<Category?> getCategoryById(int id) => _dao.getCategoryById(id);
  Future<Category?> getCategoryByName(String name) => _dao.getCategoryByName(name);
  Future<int> insertCategory(CategoriesCompanion category) => _dao.insertCategory(category);
  Future<bool> updateCategory(CategoriesCompanion category) => _dao.updateCategory(category);
  Future<int> deleteCategory(int id) => _dao.deleteCategory(id);
}

