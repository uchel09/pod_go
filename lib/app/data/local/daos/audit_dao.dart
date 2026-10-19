import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/audit_logs.dart';

part 'audit_dao.g.dart';

@DriftAccessor(tables: [AuditLogs])
class AuditDao extends DatabaseAccessor<AppDatabase> with _$AuditDaoMixin {
  AuditDao(super.db);

  /// Catatan: AuditDao bersifat APPEND-ONLY.
  /// Tidak ada method update/delete untuk menjaga integritas jejak audit.

  Future<List<AuditLog>> getAllLogs() =>
      (select(auditLogs)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Stream<List<AuditLog>> watchAllLogs() =>
      (select(auditLogs)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<int> insertLog(AuditLogsCompanion log) => into(auditLogs).insert(log);

  /// Mengambil log khusus untuk suatu entitas (misal produk tertentu)
  Future<List<AuditLog>> getLogsByEntity({
    required String entity,
    required int entityId,
    int limit = 50,
  }) {
    return (select(auditLogs)
          ..where((t) => t.entity.equals(entity) & t.entityId.equals(entityId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  /// Pagination log aktivitas dengan filter tanggal, user, kategori/jenis, dan pencarian teks.
  Future<List<AuditLog>> getLogsPage({
    required int limit,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
    String? category,
    String? searchQuery,
  }) {
    final query = select(auditLogs)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit, offset: offset);

    if (startDate != null) {
      query.where((t) => t.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.createdAt.isSmallerThanValue(endDate));
    }
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    if (category != null && category != 'Semua' && category.isNotEmpty) {
      switch (category) {
        case 'Produk':
          query.where((t) => t.action.like('product.%'));
          break;
        case 'Stok':
          query.where((t) => t.action.like('stock.%'));
          break;
        case 'Penjualan':
          query.where((t) => t.action.like('sale.%'));
          break;
        case 'Akun':
          query.where((t) => t.action.like('auth.%') | t.action.like('user.%'));
          break;
        case 'Pengaturan':
          query.where((t) => t.action.like('settings.%') | t.action.like('license.%'));
          break;
        case 'Sistem':
          query.where((t) =>
              t.action.like('category.%') |
              t.action.like('unit.%') |
              t.action.like('backup.%') |
              t.action.like('import.%') |
              t.action.like('export.%'));
          break;
      }
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where((t) => t.action.like(term) | t.detail.like(term));
    }

    return query.get();
  }

  /// Batch lookup nama display user untuk log aktivitas
  Future<Map<int, String>> getUserDisplayNames(Set<int> userIds) async {
    if (userIds.isEmpty) return const <int, String>{};
    final placeholders = List.filled(userIds.length, '?').join(', ');
    final rows = await customSelect(
      'SELECT id, display_name FROM users WHERE id IN ($placeholders)',
      variables: [for (final id in userIds) Variable<int>(id)],
    ).get();
    return {
      for (final row in rows) row.read<int>('id'): row.read<String>('display_name'),
    };
  }
}
