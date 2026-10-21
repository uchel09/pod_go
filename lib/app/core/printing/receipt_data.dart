class ReceiptItemData {
  final String name;
  final int qty;
  final int price;
  final int discount;
  final int subtotal;
  final bool restock;

  const ReceiptItemData({
    required this.name,
    required this.qty,
    required this.price,
    this.discount = 0,
    required this.subtotal,
    this.restock = true,
  });
}

class ReceiptPaymentData {
  final String method;
  final int amount;

  const ReceiptPaymentData({
    required this.method,
    required this.amount,
  });
}

class ReceiptData {
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final String invoiceNo;
  final String cashierName;
  final DateTime dateTime;
  final List<ReceiptItemData> items;
  final int subtotal;
  final int discount;
  final int tax;
  final int? taxRateBps;
  final String? taxMode;
  final String? taxName;
  final int total;
  final int paid;
  final int change;
  final List<ReceiptPaymentData> payments;
  final String? footerNotes;
  final bool isReprint;
  final bool isReturn;
  final String? returnNo;
  final String? originInvoiceNo;
  final String? returnReason;

  const ReceiptData({
    required this.storeName,
    this.storeAddress,
    this.storePhone,
    required this.invoiceNo,
    required this.cashierName,
    required this.dateTime,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    this.taxRateBps,
    this.taxMode,
    this.taxName,
    required this.total,
    required this.paid,
    required this.change,
    required this.payments,
    this.footerNotes,
    this.isReprint = false,
    this.isReturn = false,
    this.returnNo,
    this.originInvoiceNo,
    this.returnReason,
  });

  String get taxRatePercentString {
    final bps = taxRateBps ?? 0;
    if (bps <= 0) return '';
    if (bps % 100 == 0) return '${bps ~/ 100}%';
    final percent = bps / 100.0;
    return '${percent.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}%';
  }
}

