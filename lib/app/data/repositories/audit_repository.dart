import '../local/app_database.dart';
import '../local/daos/audit_dao.dart';

class AuditRepository {
  final AuditDao _dao;

  AuditRepository(this._dao);

  Future<List<AuditLog>> getAllLogs() => _dao.getAllLogs();
  Stream<List<AuditLog>> watchAllLogs() => _dao.watchAllLogs();
  Future<int> insertLog(AuditLogsCompanion log) => _dao.insertLog(log);
}

