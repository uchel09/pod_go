class ReceiptItemData {
  final String name;
  final int qty;
  final int price;
  final int discount;
  final int subtotal;

  const ReceiptItemData({
    required this.name,
    required this.qty,
    required this.price,
    this.discount = 0,
    required this.subtotal,
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
  final int total;
  final int paid;
  final int change;
  final List<ReceiptPaymentData> payments;
  final String? footerNotes;
  final bool isReprint;

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
    required this.total,
    required this.paid,
    required this.change,
    required this.payments,
    this.footerNotes,
    this.isReprint = false,
  });
}

