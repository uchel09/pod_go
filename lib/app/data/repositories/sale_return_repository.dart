import 'package:drift/drift.dart';
import 'package:get/get.dart' hide Value;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_actions.dart';
import '../../core/permissions/permission_keys.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/tax/tax_calculator.dart';
import '../../core/utils/app_exception.dart';
import '../local/app_database.dart';
import '../local/daos/sale_dao.dart';
import '../local/daos/sale_return_dao.dart';
import 'stock_repository.dart';

class CreateReturnItemInput {
  final int saleItemId;
  final int productId;
  final String productName;
  final int qty;
  final int unitPrice;
  final int costPrice;
  final bool restock;

  const CreateReturnItemInput({
    required this.saleItemId,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.costPrice,
    this.restock = true,
  });

  int get subtotal => qty * unitPrice;
}

class CreateReturnInput {
  final int saleId;
  final String deviceId;
  final List<CreateReturnItemInput> items;
  final String refundMethod; // 'cash' | 'other'
  final String reason;
  final int? createdBy;

  const CreateReturnInput({
    required this.saleId,
    required this.deviceId,
    required this.items,
    this.refundMethod = 'cash',
    required this.reason,
    this.createdBy,
  });
}

class ReturnableSaleItem {
  final SaleItem saleItem;
  final int returnedQty;
  final int availableQty;

  const ReturnableSaleItem({
    required this.saleItem,
    required this.returnedQty,
    required this.availableQty,
  });
}

class SaleReturnRepository {
  final AppDatabase _db;
  final SaleReturnDao _saleReturnDao;
  final SaleDao _saleDao;
  final StockRepository _stockRepo;

  SaleReturnRepository(
    this._db,
    this._saleReturnDao,
    this._saleDao,
    this._stockRepo,
  );

  /// Menghasilkan nomor retur unik dengan format RTN-YYYYMMDD-NNNN
  Future<String> generateReturnNo({DateTime? date}) async {
    final now = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final prefix = 'RTN-$dateStr-';

    final count = await _saleReturnDao.countReturnsByPrefix(prefix);
    int seq = count + 1;
    String candidate = '$prefix${seq.toString().padLeft(4, '0')}';

    while (await _saleReturnDao.getReturnByNo(candidate) != null) {
      seq++;
      candidate = '$prefix${seq.toString().padLeft(4, '0')}';
    }

    return candidate;
  }

  /// Mengambil daftar item penjualan yang masih dapat diretur (sisa qty > 0)
  Future<List<ReturnableSaleItem>> getReturnableItems(int saleId) async {
    final saleItems = await _saleDao.getItemsBySaleId(saleId);
    final returnedMap = await _saleReturnDao.getReturnedQtyPerSaleItem(saleId);

    return saleItems.map((item) {
      final returned = returnedMap[item.id] ?? 0;
      final available = (item.qty - returned).clamp(0, item.qty);
      return ReturnableSaleItem(
        saleItem: item,
        returnedQty: returned,
        availableQty: available,
      );
    }).toList();
  }

  /// Membuat transaksi retur barang parsial secara ATOMIK dalam satu database.transaction()
  Future<SaleReturnDetail> createReturn(CreateReturnInput input) async {
    // 1. Dual-layer permission check: can('pos.return')
    if (Get.isRegistered<PermissionService>()) {
      if (!PermissionService.to.can(PermissionKeys.posReturn)) {
        throw const AppException(
          'Akses ditolak: Anda tidak memiliki izin untuk memproses retur transaksi (pos.return).',
          code: 'FORBIDDEN_RETURN',
        );
      }
    }

    final trimmedReason = input.reason.trim();
    if (trimmedReason.length < 5) {
      throw const AppException(
        'Alasan retur wajib diisi minimal 5 karakter.',
        code: 'INVALID_RETURN_REASON',
      );
    }

    final validItems = input.items.where((i) => i.qty > 0).toList();
    if (validItems.isEmpty) {
      throw const AppException(
        'Pilih minimal satu barang dengan jumlah kuantitas lebih dari 0 untuk diretur.',
        code: 'EMPTY_RETURN_ITEMS',
      );
    }

    final currentUserId =
        input.createdBy ??
        (Get.isRegistered<AuthService>()
            ? AuthService.to.currentUser.value?.id
            : null);

    if (currentUserId == null) {
      throw const AppException('Sesi kasir tidak valid.');
    }

    return await _db.transaction(() async {
      // 2. Ambil transaksi penjualan asal & validasi status
      final sale = await _saleDao.getSaleById(input.saleId);
      if (sale == null) {
        throw AppException(
          'Transaksi penjualan dengan ID ${input.saleId} tidak ditemukan.',
          code: 'SALE_NOT_FOUND',
        );
      }

      if (sale.status == 'void') {
        throw const AppException(
          'Transaksi yang sudah dibatalkan (void) tidak dapat diretur.',
          code: 'SALE_ALREADY_VOIDED',
        );
      }

      if (sale.status != 'completed') {
        throw AppException(
          'Hanya transaksi berstatus selesai yang dapat diretur (Status: ${sale.status}).',
          code: 'INVALID_STATUS_FOR_RETURN',
        );
      }

      // 3. Validasi batas kuantitas di dalam transaksi
      final saleItems = await _saleDao.getItemsBySaleId(sale.id);
      final saleItemMap = {for (final item in saleItems) item.id: item};
      final returnedMap = await _saleReturnDao.getReturnedQtyPerSaleItem(
        sale.id,
      );

      int subtotalRefund = 0;
      for (final retItem in validItems) {
        final originItem = saleItemMap[retItem.saleItemId];
        if (originItem == null || originItem.productId != retItem.productId) {
          throw AppException(
            'Barang "${retItem.productName}" tidak sesuai dengan transaksi asal.',
            code: 'ITEM_MISMATCH',
          );
        }

        final alreadyReturned = returnedMap[originItem.id] ?? 0;
        final maxAvailable = originItem.qty - alreadyReturned;

        if (retItem.qty > maxAvailable) {
          throw AppException(
            'Jumlah retur untuk "${retItem.productName}" melebihi sisa yang dapat diretur (Maksimal: $maxAvailable, Diminta: ${retItem.qty}).',
            code: 'EXCEEDED_RETURN_QTY',
          );
        }

        subtotalRefund += retItem.subtotal;
      }

      // 4. Perhitungan pajak proporsional & guard total refund
      int taxRefund = 0;
      int totalRefund = subtotalRefund;

      if (sale.taxRateBps != null && sale.taxRateBps! > 0 && sale.tax > 0) {
        if (sale.taxMode == 'inclusive') {
          taxRefund = TaxCalculator.calculateInclusive(
            subtotalRefund,
            sale.taxRateBps!,
          );
          totalRefund = subtotalRefund;
        } else {
          taxRefund = TaxCalculator.calculateExclusive(
            subtotalRefund,
            sale.taxRateBps!,
          );
          totalRefund = subtotalRefund + taxRefund;
        }
      }

      // Pastikan akumulasi retur tidak melebihi total transaksi asal
      final previousRefundTotal = await _saleReturnDao
          .getTotalRefundAmountForSale(sale.id);
      final remainingMaxRefund = (sale.total - previousRefundTotal).clamp(
        0,
        sale.total,
      );
      if (totalRefund > remainingMaxRefund) {
        totalRefund = remainingMaxRefund;
        if (sale.taxMode == 'exclusive') {
          taxRefund = (totalRefund - subtotalRefund).clamp(0, totalRefund);
        }
      }

      // 5. Generate returnNo & UUID
      final now = DateTime.now();
      final returnNo = await generateReturnNo(date: now);
      final returnUuid = const Uuid().v4();

      // 6. Simpan SaleReturn
      final returnId = await _saleReturnDao.insertReturn(
        SaleReturnsCompanion(
          uuid: Value(returnUuid),
          deviceId: Value(input.deviceId),
          returnNo: Value(returnNo),
          saleId: Value(sale.id),
          subtotal: Value(subtotalRefund),
          taxRefund: Value(taxRefund),
          total: Value(totalRefund),
          refundMethod: Value(input.refundMethod),
          reason: Value(trimmedReason),
          createdBy: Value(currentUserId),
          createdAt: Value(now),
        ),
      );

      // 7. Simpan SaleReturnItems & Kembalikan stok bila restock == true
      final insertedItems = <SaleReturnItem>[];
      for (final retItem in validItems) {
        final itemId = await _saleReturnDao.insertReturnItem(
          SaleReturnItemsCompanion(
            returnId: Value(returnId),
            saleItemId: Value(retItem.saleItemId),
            productId: Value(retItem.productId),
            productName: Value(retItem.productName),
            qty: Value(retItem.qty),
            unitPrice: Value(retItem.unitPrice),
            costPrice: Value(retItem.costPrice),
            restock: Value(retItem.restock),
            subtotal: Value(retItem.subtotal),
          ),
        );

        insertedItems.add(
          SaleReturnItem(
            id: itemId,
            returnId: returnId,
            saleItemId: retItem.saleItemId,
            productId: retItem.productId,
            productName: retItem.productName,
            qty: retItem.qty,
            unitPrice: retItem.unitPrice,
            costPrice: retItem.costPrice,
            restock: retItem.restock,
            subtotal: retItem.subtotal,
          ),
        );

        // Hanya kembalikan stok jika restock == true (barang tidak rusak)
        if (retItem.restock) {
          await _stockRepo.applyMovement(
            productId: retItem.productId,
            type: 'return',
            qtyChange: retItem.qty,
            refTable: 'sale_returns',
            refId: returnId,
            note: 'Retur $returnNo (Nota ${sale.invoiceNo})',
            createdBy: currentUserId,
          );
        }
      }

      // 8. Catat jejak audit
      if (Get.isRegistered<AuditService>()) {
        await AuditService.to.log(
          action: AuditActions.saleReturn,
          entity: 'sale_returns',
          entityId: returnId,
          detail: {
            'invoiceNo': sale.invoiceNo,
            'returnNo': returnNo,
            'total': totalRefund,
            'reason': trimmedReason,
          },
        );
      }

      final createdReturn = SaleReturn(
        id: returnId,
        uuid: returnUuid,
        deviceId: input.deviceId,
        returnNo: returnNo,
        saleId: sale.id,
        subtotal: subtotalRefund,
        taxRefund: taxRefund,
        total: totalRefund,
        refundMethod: input.refundMethod,
        reason: trimmedReason,
        createdBy: currentUserId,
        createdAt: now,
      );

      final user = await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(currentUserId))).getSingleOrNull();

      return SaleReturnDetail(
        saleReturn: createdReturn,
        items: insertedItems,
        cashierName: user?.displayName ?? 'Kasir',
        invoiceNo: sale.invoiceNo,
      );
    });
  }

  Future<List<SaleReturn>> getReturnsBySaleId(int saleId) =>
      _saleReturnDao.getReturnsBySaleId(saleId);

  Future<SaleReturnDetail?> getReturnDetail(int returnId) =>
      _saleReturnDao.getReturnDetail(returnId);

  Future<List<SaleReturnEntry>> getReturnsPage({
    int limit = 30,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) => _saleReturnDao.getReturnsPage(
    limit: limit,
    offset: offset,
    startDate: startDate,
    endDate: endDate,
    searchQuery: searchQuery,
  );

  Future<bool> hasReturnsForSale(int saleId) =>
      _saleReturnDao.hasReturnsForSale(saleId);
}
