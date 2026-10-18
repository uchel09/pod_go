import 'package:intl/intl.dart';

String formatRupiah(int amount) {
  final formatter = NumberFormat.decimalPattern('id_ID');
  if (amount < 0) {
    return '-Rp ${formatter.format(amount.abs())}';
  }
  return 'Rp ${formatter.format(amount)}';
}

