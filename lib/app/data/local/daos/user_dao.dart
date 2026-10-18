import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users.dart';

part 'user_dao.g.dart';

@DriftAccessor(tables: [Users])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  Future<List<User>> getAllUsers() => select(users).get();

  Stream<List<User>> watchAllUsers() => select(users).watch();

  Future<User?> getUserById(int id) =>
      (select(users)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<User?> getUserByUsername(String username) =>
      (select(users)..where((t) => t.username.equals(username))).getSingleOrNull();

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  Future<bool> updateUser(UsersCompanion user) => update(users).replace(user);

  Future<int> deleteUser(int id) => (delete(users)..where((t) => t.id.equals(id))).go();
}

