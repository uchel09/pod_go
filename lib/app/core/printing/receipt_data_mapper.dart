import '../../data/local/app_database.dart';
import 'receipt_data.dart';

/// Teks footer struk bawaan.
const String kDefaultReceiptFooter = 'Terima kasih atas kunjungan Anda!';

/// Label tampilan untuk metode pembayaran ('cash', 'qris', 'transfer', 'other').
String paymentMethodLabel(String method) {
  switch (method.toLowerCase()) {
    case 'cash':
    case 'tunai':
      return 'Tunai';
    case 'qris':
      return 'QRIS';
    case 'transfer':
      return 'Transfer';
    default:
      return 'Lainnya';
  }
}

/// Apakah transaksi mengandung pembayaran tunai (dasar pembukaan laci kasir).
bool hasCashPayment(Iterable<String> methods) {
  return methods.any((m) {
    final lower = m.toLowerCase();
    return lower == 'cash' || lower == 'tunai';
  });
}

/// Memetakan data transaksi tersimpan (Drift) menjadi [ReceiptData] netral.
///
/// Seluruh angka diambil dari baris yang sudah tersimpan (snapshot), bukan dihitung
/// ulang, sehingga struk cetak ulang selalu identik dengan transaksi aslinya.
ReceiptData buildReceiptData({
  required Store? store,
  required String cashierName,
  required Sale sale,
  required List<SaleItem> items,
  required List<Payment> payments,
  String? taxName,
  bool isReprint = false,
}) {
  return ReceiptData(
    storeName: store?.name ?? 'TOKO UMKM',
    storeAddress: store?.address,
    storePhone: store?.phone,
    invoiceNo: sale.invoiceNo,
    cashierName: cashierName,
    dateTime: sale.createdAt,
    items: items
        .map(
          (i) => ReceiptItemData(
            name: i.productName,
            qty: i.qty,
            price: i.price,
            discount: i.discount,
            subtotal: i.subtotal,
          ),
        )
        .toList(),
    subtotal: sale.subtotal,
    discount: sale.discount,
    tax: sale.tax,
    taxRateBps: sale.taxRateBps,
    taxMode: sale.taxMode,
    taxName: taxName ?? 'PPN',
    total: sale.total,
    paid: sale.paid,
    change: sale.change,
    payments: payments
        .map((p) => ReceiptPaymentData(method: p.method, amount: p.amount))
        .toList(),
    footerNotes: kDefaultReceiptFooter,
    isReprint: isReprint,
  );
}

/// Memetakan data retur tersimpan (Drift) menjadi [ReceiptData] untuk cetak bukti retur.
ReceiptData buildReturnReceiptData({
  required Store? store,
  required String cashierName,
  required SaleReturn saleReturn,
  required List<SaleReturnItem> items,
  required String originInvoiceNo,
  String? taxName,
}) {
  return ReceiptData(
    storeName: store?.name ?? 'TOKO UMKM',
    storeAddress: store?.address,
    storePhone: store?.phone,
    invoiceNo: saleReturn.returnNo,
    cashierName: cashierName,
    dateTime: saleReturn.createdAt,
    items: items
        .map(
          (i) => ReceiptItemData(
            name: i.productName,
            qty: i.qty,
            price: i.unitPrice,
            subtotal: i.subtotal,
            restock: i.restock,
          ),
        )
        .toList(),
    subtotal: saleReturn.subtotal,
    discount: 0,
    tax: saleReturn.taxRefund,
    taxName: taxName ?? 'PPN',
    total: saleReturn.total,
    paid: saleReturn.total,
    change: 0,
    payments: [
      ReceiptPaymentData(
        method: saleReturn.refundMethod,
        amount: saleReturn.total,
      ),
    ],
    footerNotes: 'Barang retur telah diverifikasi oleh kasir & toko.',
    isReturn: true,
    returnNo: saleReturn.returnNo,
    originInvoiceNo: originInvoiceNo,
    returnReason: saleReturn.reason,
  );
}

