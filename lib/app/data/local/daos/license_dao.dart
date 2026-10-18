import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/licenses.dart';

part 'license_dao.g.dart';

@DriftAccessor(tables: [Licenses])
class LicenseDao extends DatabaseAccessor<AppDatabase> with _$LicenseDaoMixin {
  LicenseDao(super.db);

  Future<License?> getActiveLicense() => (select(licenses)
        ..orderBy([(t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .getSingleOrNull();

  Stream<License?> watchActiveLicense() => (select(licenses)
        ..orderBy([(t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<int> insertLicense(LicensesCompanion license) => into(licenses).insert(license);

  Future<bool> updateLicense(LicensesCompanion license) =>
      update(licenses).replace(license);
}

