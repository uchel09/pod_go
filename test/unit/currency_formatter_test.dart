import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter Tests', () {
    test('formatRupiah formats positive amounts correctly', () {
      expect(formatRupiah(1250000), 'Rp 1.250.000');
      expect(formatRupiah(12500), 'Rp 12.500');
      expect(formatRupiah(500), 'Rp 500');
      expect(formatRupiah(0), 'Rp 0');
    });

    test('formatRupiah formats negative amounts correctly', () {
      expect(formatRupiah(-12500), '-Rp 12.500');
      expect(formatRupiah(-1250000), '-Rp 1.250.000');
    });
  });
}

