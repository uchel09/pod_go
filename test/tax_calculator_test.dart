import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/tax/tax_calculator.dart';

void main() {
  group('TaxCalculator Unit Tests', () {
    test('calculateExclusive: 11% dari Rp 100.000 menghasilkan Rp 11.000 (Total Rp 111.000)', () {
      const basis = 100000;
      const rateBps = 1100; // 11%

      final tax = TaxCalculator.calculateExclusive(basis, rateBps);
      expect(tax, equals(11000));

      final result = TaxCalculator.calculate(
        basis: basis,
        rateBps: rateBps,
        mode: TaxCalculator.modeExclusive,
        isEnabled: true,
      );
      expect(result.tax, equals(11000));
      expect(result.total, equals(111000));
      expect(result.basis, equals(100000));
      expect(result.ratePercentString, equals('11%'));
    });

    test('calculateInclusive: 11% dari Rp 111.000 menghasilkan Rp 11.000 (Total tetap Rp 111.000)', () {
      const basis = 111000;
      const rateBps = 1100; // 11%

      final tax = TaxCalculator.calculateInclusive(basis, rateBps);
      expect(tax, equals(11000));

      final result = TaxCalculator.calculate(
        basis: basis,
        rateBps: rateBps,
        mode: TaxCalculator.modeInclusive,
        isEnabled: true,
      );
      expect(result.tax, equals(11000));
      expect(result.total, equals(111000));
      expect(result.basis, equals(111000));
      expect(result.ratePercentString, equals('11%'));
    });

    test('Pembulatan half-up integer Rupiah bekerja presisi tanpa double', () {
      // Basis 105 dengan 11% (1100 bps) -> 11.55 -> bulat ke 12
      final taxUp = TaxCalculator.calculateExclusive(105, 1100);
      expect(taxUp, equals(12));

      // Basis 104 dengan 11% (1100 bps) -> 11.44 -> bulat ke 11
      final taxDown = TaxCalculator.calculateExclusive(104, 1100);
      expect(taxDown, equals(11));
    });

    test('Pajak dinonaktifkan (isEnabled = false) atau rate = 0 mengembalikan tax = 0', () {
      final disabled = TaxCalculator.calculate(
        basis: 100000,
        rateBps: 1100,
        mode: TaxCalculator.modeExclusive,
        isEnabled: false,
      );
      expect(disabled.tax, equals(0));
      expect(disabled.total, equals(100000));

      final zeroRate = TaxCalculator.calculate(
        basis: 100000,
        rateBps: 0,
        mode: TaxCalculator.modeExclusive,
        isEnabled: true,
      );
      expect(zeroRate.tax, equals(0));
      expect(zeroRate.total, equals(100000));
    });

    test('ratePercentString format angka bulat dan desimal dengan rapi', () {
      final res1 = TaxCalculator.calculate(
        basis: 10000,
        rateBps: 1100,
        mode: 'exclusive',
      );
      expect(res1.ratePercentString, equals('11%'));

      final res2 = TaxCalculator.calculate(
        basis: 10000,
        rateBps: 1150,
        mode: 'exclusive',
      );
      expect(res2.ratePercentString, equals('11.5%'));

      final res3 = TaxCalculator.calculate(
        basis: 10000,
        rateBps: 1125,
        mode: 'exclusive',
      );
      expect(res3.ratePercentString, equals('11.25%'));
    });
  });
}

