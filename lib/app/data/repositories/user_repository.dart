import '../local/app_database.dart';
import '../local/daos/user_dao.dart';

class UserRepository {
  final UserDao _dao;

  UserRepository(this._dao);

  Future<List<User>> getAllUsers() => _dao.getAllUsers();
  Stream<List<User>> watchAllUsers() => _dao.watchAllUsers();
  Future<User?> getUserById(int id) => _dao.getUserById(id);
  Future<User?> getUserByUsername(String username) => _dao.getUserByUsername(username);
  Future<int> insertUser(UsersCompanion user) => _dao.insertUser(user);
  Future<bool> updateUser(UsersCompanion user) => _dao.updateUser(user);
  Future<int> deleteUser(int id) => _dao.deleteUser(id);
}

