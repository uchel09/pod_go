import 'dart:convert';
import '../local/app_database.dart';
import '../local/daos/audit_dao.dart';

class AuditEntry {
  final AuditLog log;
  final String userName;

  const AuditEntry({
    required this.log,
    required this.userName,
  });

  int get id => log.id;
  int? get userId => log.userId;
  String get action => log.action;
  String get entity => log.entity;
  int? get entityId => log.entityId;
  String? get detail => log.detail;
  String? get deviceId => log.deviceId;
  DateTime get createdAt => log.createdAt;

  Map<String, dynamic> get parsedDetail {
    if (log.detail == null || log.detail!.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(log.detail!);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }
}

class AuditRepository {
  final AuditDao _dao;

  AuditRepository(this._dao);

  Future<List<AuditLog>> getAllLogs() => _dao.getAllLogs();
  Stream<List<AuditLog>> watchAllLogs() => _dao.watchAllLogs();
  Future<int> insertLog(AuditLogsCompanion log) => _dao.insertLog(log);

  Future<List<AuditEntry>> getLogsByEntity({
    required String entity,
    required int entityId,
    int limit = 50,
  }) async {
    final logs = await _dao.getLogsByEntity(entity: entity, entityId: entityId, limit: limit);
    if (logs.isEmpty) return const <AuditEntry>[];
    final userIds = logs.map((l) => l.userId).whereType<int>().toSet();
    final names = await _dao.getUserDisplayNames(userIds);
    return logs.map((log) {
      final userName = log.userId != null ? (names[log.userId] ?? 'User #${log.userId}') : 'Sistem';
      return AuditEntry(log: log, userName: userName);
    }).toList();
  }

  Future<List<AuditEntry>> getLogsPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
    String? category,
    String? searchQuery,
  }) async {
    final logs = await _dao.getLogsPage(
      limit: limit,
      offset: offset,
      startDate: startDate,
      endDate: endDate,
      userId: userId,
      category: category,
      searchQuery: searchQuery,
    );

    if (logs.isEmpty) return const <AuditEntry>[];

    final userIds = logs.map((l) => l.userId).whereType<int>().toSet();
    final names = await _dao.getUserDisplayNames(userIds);

    return logs.map((log) {
      final userName = log.userId != null ? (names[log.userId] ?? 'User #${log.userId}') : 'Sistem';
      return AuditEntry(log: log, userName: userName);
    }).toList();
  }

  Future<Map<int, String>> getUserDisplayNames(Set<int> userIds) =>
      _dao.getUserDisplayNames(userIds);
}
