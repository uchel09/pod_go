import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/audit_logs.dart';

part 'audit_dao.g.dart';

@DriftAccessor(tables: [AuditLogs])
class AuditDao extends DatabaseAccessor<AppDatabase> with _$AuditDaoMixin {
  AuditDao(super.db);

  Future<List<AuditLog>> getAllLogs() => select(auditLogs).get();

  Stream<List<AuditLog>> watchAllLogs() => select(auditLogs).watch();

  Future<int> insertLog(AuditLogsCompanion log) => into(auditLogs).insert(log);
}

