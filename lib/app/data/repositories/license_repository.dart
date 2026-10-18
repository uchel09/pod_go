import '../local/app_database.dart';
import '../local/daos/license_dao.dart';

class LicenseRepository {
  final LicenseDao _dao;

  LicenseRepository(this._dao);

  Future<License?> getActiveLicense() => _dao.getActiveLicense();
  Stream<License?> watchActiveLicense() => _dao.watchActiveLicense();
  Future<int> insertLicense(LicensesCompanion license) => _dao.insertLicense(license);
  Future<bool> updateLicense(LicensesCompanion license) => _dao.updateLicense(license);
}

