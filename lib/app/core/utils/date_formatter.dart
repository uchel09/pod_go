import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static String formatDate(DateTime date) {
    try {
      return DateFormat('d MMMM yyyy', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('d MMMM yyyy').format(date);
    }
  }

  static String formatFullDate(DateTime date) {
    try {
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('EEEE, d MMMM yyyy').format(date);
    }
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  static String formatDateTime(DateTime date) {
    try {
      return DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('d MMM yyyy, HH:mm').format(date);
    }
  }
}
