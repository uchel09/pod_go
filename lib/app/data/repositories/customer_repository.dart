import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/features/feature_enum.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_gate.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/customer_dao.dart';

class CreateCustomerInput {
  final String name;
  final String? phone;
  final String? address;
  final String? note;
  final int? creditLimit;

  const CreateCustomerInput({
    required this.name,
    this.phone,
    this.address,
    this.note,
    this.creditLimit,
  });
}

class UpdateCustomerInput {
  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? note;
  final int? creditLimit;
  final bool isActive;

  const UpdateCustomerInput({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.note,
    this.creditLimit,
    this.isActive = true,
  });
}

class RecordCustomerPaymentInput {
  final int customerId;
  final int amount;
  final String method; // 'cash' | 'transfer' | 'other'
  final String? note;
  final String deviceId;
  final int? createdBy;

  const RecordCustomerPaymentInput({
    required this.customerId,
    required this.amount,
    this.method = 'cash',
    this.note,
    required this.deviceId,
    this.createdBy,
  });
}

class CustomerRepository {
  final AppDatabase _db;
  final CustomerDao _customerDao;
  final FeatureGate? _featureGate;
  final PermissionService? _permissionService;
  final AuditService? _auditService;

  CustomerRepository(
    this._db,
    this._customerDao, {
    FeatureGate? featureGate,
    PermissionService? permissionService,
    AuditService? auditService,
  })  : _featureGate = featureGate,
        _permissionService = permissionService,
        _auditService = auditService;

  AppDatabase get db => _db;

  bool _isFeatureEnabled(Feature feature) {
    if (_featureGate != null) return _featureGate.isEnabled(feature);
    if (Get.isRegistered<FeatureGate>()) return FeatureGate.to.isEnabled(feature);
    return false;
  }

  void _requireFeature(Feature feature) {
    if (!_isFeatureEnabled(feature)) {
      throw const AppException(
        'Fitur Pelanggan & Kasbon memerlukan lisensi Semi Premium ke atas.',
        code: 'FEATURE_LOCKED',
      );
    }
  }

  bool _hasPermission(String key) {
    if (_permissionService != null) return _permissionService.can(key);
    if (Get.isRegistered<PermissionService>()) return PermissionService.to.can(key);
    return true;
  }

  void _requirePermission(String key, String message) {
    if (!_hasPermission(key)) {
      throw AppException(message, code: 'FORBIDDEN');
    }
  }

  int _resolveUserId(int? explicitId) {
    if (explicitId != null) return explicitId;
    if (Get.isRegistered<AuthService>()) {
      final user = AuthService.to.currentUser.value;
      if (user != null) return user.id;
    }
    return 1;
  }

  /// Membuat data pelanggan baru.
  Future<CustomerWithBalance> createCustomer(
    CreateCustomerInput input, {
    String? deviceId,
  }) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerManage,
      'Akses ditolak: Anda tidak memiliki izin untuk menambah pelanggan (customer.manage).',
    );

    final trimmedName = input.name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException(
        'Nama pelanggan wajib diisi.',
        code: 'INVALID_NAME',
      );
    }

    if (input.creditLimit != null && input.creditLimit! < 0) {
      throw const AppException(
        'Batas limit kredit tidak boleh negatif.',
        code: 'INVALID_CREDIT_LIMIT',
      );
    }

    final devId = deviceId ?? 'device-main';
    final uuid = const Uuid().v4();
    final now = DateTime.now();

    final id = await _customerDao.insertCustomer(
      CustomersCompanion(
        uuid: Value(uuid),
        deviceId: Value(devId),
        name: Value(trimmedName),
        phone: Value(input.phone?.trim().isNotEmpty == true ? input.phone!.trim() : null),
        address: Value(input.address?.trim().isNotEmpty == true ? input.address!.trim() : null),
        note: Value(input.note?.trim().isNotEmpty == true ? input.note!.trim() : null),
        creditLimit: Value(input.creditLimit),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final created = (await _customerDao.getCustomerWithBalance(id))!;

    // Jejak audit
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    if (audit != null) {
      await audit.log(
        action: AuditActions.customerCreate,
        entity: 'customers',
        entityId: id,
        detail: {
          'name': trimmedName,
          'phone': input.phone,
          'creditLimit': input.creditLimit,
        },
      );
    }

    return created;
  }

  /// Memperbarui profil pelanggan.
  Future<CustomerWithBalance> updateCustomer(
    UpdateCustomerInput input, {
    String? deviceId,
  }) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerManage,
      'Akses ditolak: Anda tidak memiliki izin untuk mengedit pelanggan (customer.manage).',
    );

    final trimmedName = input.name.trim();
    if (trimmedName.isEmpty) {
      throw const AppException(
        'Nama pelanggan tidak boleh kosong.',
        code: 'INVALID_NAME',
      );
    }

    if (input.creditLimit != null && input.creditLimit! < 0) {
      throw const AppException(
        'Batas limit kredit tidak boleh negatif.',
        code: 'INVALID_CREDIT_LIMIT',
      );
    }

    final existing = await _customerDao.getCustomerById(input.id);
    if (existing == null) {
      throw const AppException(
        'Data pelanggan tidak ditemukan.',
        code: 'CUSTOMER_NOT_FOUND',
      );
    }

    final now = DateTime.now();
    await _customerDao.updateCustomer(
      CustomersCompanion(
        id: Value(input.id),
        uuid: Value(existing.uuid),
        deviceId: Value(deviceId ?? existing.deviceId),
        name: Value(trimmedName),
        phone: Value(input.phone?.trim().isNotEmpty == true ? input.phone!.trim() : null),
        address: Value(input.address?.trim().isNotEmpty == true ? input.address!.trim() : null),
        note: Value(input.note?.trim().isNotEmpty == true ? input.note!.trim() : null),
        creditLimit: Value(input.creditLimit),
        isActive: Value(input.isActive),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(now),
      ),
    );

    final updated = (await _customerDao.getCustomerWithBalance(input.id))!;

    // Audit log
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    if (audit != null) {
      if (existing.isActive && !input.isActive) {
        await audit.log(
          action: AuditActions.customerDeactivate,
          entity: 'customers',
          entityId: input.id,
          detail: {'name': trimmedName},
        );
      } else {
        await audit.log(
          action: AuditActions.customerUpdate,
          entity: 'customers',
          entityId: input.id,
          detail: {
            'name': trimmedName,
            'creditLimit': input.creditLimit,
            'isActive': input.isActive,
          },
        );
      }
    }

    return updated;
  }

  /// Menonaktifkan status pelanggan.
  Future<void> deactivateCustomer(int id) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerManage,
      'Akses ditolak: Anda tidak memiliki izin untuk menonaktifkan pelanggan.',
    );

    final customer = await _customerDao.getCustomerById(id);
    if (customer == null) {
      throw const AppException('Pelanggan tidak ditemukan.', code: 'CUSTOMER_NOT_FOUND');
    }

    await _customerDao.deactivateCustomer(id);

    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    if (audit != null) {
      await audit.log(
        action: AuditActions.customerDeactivate,
        entity: 'customers',
        entityId: id,
        detail: {'name': customer.name},
      );
    }
  }

  /// Mengaktifkan kembali status pelanggan.
  Future<void> activateCustomer(int id) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerManage,
      'Akses ditolak: Anda tidak memiliki izin untuk mengaktifkan pelanggan.',
    );

    await _customerDao.activateCustomer(id);
  }

  /// Menghapus pelanggan (hanya jika belum memiliki transaksi sama sekali).
  Future<void> deleteCustomer(int id) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerManage,
      'Akses ditolak: Anda tidak memiliki izin untuk menghapus pelanggan.',
    );

    final hasTx = await _customerDao.hasTransactions(id);
    if (hasTx) {
      throw const AppException(
        'Pelanggan yang sudah memiliki transaksi tidak dapat dihapus. Silakan nonaktifkan pelanggan.',
        code: 'CUSTOMER_HAS_TRANSACTIONS',
      );
    }

    await _customerDao.deleteCustomer(id);
  }

  /// Mengambil data pelanggan tunggal beserta saldonya.
  Future<CustomerWithBalance?> getCustomer(int id) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat data pelanggan.',
    );
    return _customerDao.getCustomerWithBalance(id);
  }

  /// Mengambil daftar pelanggan dengan pencarian dan filter hutang.
  Future<List<CustomerWithBalance>> getCustomers({
    String? query,
    bool onlyWithDebt = false,
    int limit = 50,
    int offset = 0,
  }) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat pelanggan.',
    );
    return _customerDao.getCustomersWithBalances(
      query: query,
      onlyWithDebt: onlyWithDebt,
      limit: limit,
      offset: offset,
    );
  }

  /// Mengambil saldo kasbon pelanggan terkini (dihitung dinamis).
  Future<int> getCustomerBalance(int customerId) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat saldo hutang pelanggan.',
    );
    return _customerDao.getCustomerBalance(customerId);
  }

  /// Mengambil buku pembantu piutang (riwayat kasbon, pembayaran, dan retur) seorang pelanggan.
  Future<List<CustomerLedgerItem>> getCustomerLedger(int customerId) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat riwayat hutang pelanggan.',
    );
    return _customerDao.getCustomerLedger(customerId);
  }

  /// Mencatat pelunasan hutang pelanggan (pembayaran kasbon).
  Future<int> recordPayment(RecordCustomerPaymentInput input) async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerCollect,
      'Akses ditolak: Anda tidak memiliki izin untuk menerima pelunasan kasbon (customer.collect).',
    );

    if (input.amount <= 0) {
      throw const AppException(
        'Nominal pelunasan kasbon harus lebih dari Rp 0.',
        code: 'INVALID_AMOUNT',
      );
    }

    final customer = await _customerDao.getCustomerById(input.customerId);
    if (customer == null) {
      throw const AppException('Data pelanggan tidak ditemukan.', code: 'CUSTOMER_NOT_FOUND');
    }

    // Validasi saldo: pelunasan tidak boleh melebihi sisa hutang
    final currentBalance = await _customerDao.getCustomerBalance(input.customerId);
    if (input.amount > currentBalance) {
      throw AppException(
        'Nominal pelunasan (${input.amount}) melebihi sisa hutang pelanggan ($currentBalance).',
        code: 'EXCESSIVE_PAYMENT',
      );
    }

    final userId = _resolveUserId(input.createdBy);
    final uuid = const Uuid().v4();
    final now = DateTime.now();

    final paymentId = await _customerDao.insertCustomerPayment(
      CustomerPaymentsCompanion(
        uuid: Value(uuid),
        deviceId: Value(input.deviceId),
        customerId: Value(input.customerId),
        amount: Value(input.amount),
        method: Value(input.method),
        note: Value(input.note?.trim().isNotEmpty == true ? input.note!.trim() : null),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    // Audit log
    final audit = _auditService ?? (Get.isRegistered<AuditService>() ? AuditService.to : null);
    if (audit != null) {
      await audit.log(
        action: AuditActions.customerPaymentReceived,
        entity: 'customer_payments',
        entityId: paymentId,
        detail: {
          'customerId': input.customerId,
          'customerName': customer.name,
          'amount': input.amount,
          'method': input.method,
          'note': input.note,
        },
      );
    }

    return paymentId;
  }

  /// Mengambil total seluruh piutang yang beredar di toko.
  Future<int> getTotalReceivables() async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat total piutang.',
    );
    return _customerDao.getTotalReceivables();
  }

  /// Mengambil laporan umur piutang (Aging Report) untuk seluruh pelanggan.
  Future<List<CustomerAgingItem>> getAgingReport() async {
    _requireFeature(Feature.customerCredit);
    _requirePermission(
      PermissionKeys.customerView,
      'Akses ditolak: Anda tidak memiliki izin untuk melihat laporan umur piutang.',
    );
    return _customerDao.getAgingReport();
  }
}

