import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/discount/discount_calculator.dart';

void main() {
  group('DiscountCalculator - halfUpDivide', () {
    test('exact division', () {
      expect(DiscountCalculator.halfUpDivide(10, 2), equals(5));
      expect(DiscountCalculator.halfUpDivide(100, 10), equals(10));
    });

    test('half up rounding (.5 rounds up)', () {
      // 5 / 2 = 2.5 -> 3
      expect(DiscountCalculator.halfUpDivide(5, 2), equals(3));
      // 15 / 10 = 1.5 -> 2
      expect(DiscountCalculator.halfUpDivide(15, 10), equals(2));
      // 14 / 10 = 1.4 -> 1
      expect(DiscountCalculator.halfUpDivide(14, 10), equals(1));
      // 16 / 10 = 1.6 -> 2
      expect(DiscountCalculator.halfUpDivide(16, 10), equals(2));
    });

    test('edge cases with zero/negative', () {
      expect(DiscountCalculator.halfUpDivide(0, 10), equals(0));
      expect(DiscountCalculator.halfUpDivide(10, 0), equals(0));
      expect(DiscountCalculator.halfUpDivide(-10, 5), equals(0));
    });
  });

  group('DiscountCalculator - calculateItemDiscount', () {
    test('nominal discount normal case', () {
      final res = DiscountCalculator.calculateItemDiscount(
        unitPrice: 20000,
        qty: 3,
        discountValue: 2000,
        isPercent: false,
      );
      expect(res.unitDiscount, equals(2000));
      expect(res.totalDiscount, equals(6000));
      expect(res.subtotal, equals(54000)); // (20000 - 2000) * 3
    });

    test('nominal discount exceeds unit price is clamped', () {
      final res = DiscountCalculator.calculateItemDiscount(
        unitPrice: 15000,
        qty: 2,
        discountValue: 25000,
        isPercent: false,
      );
      expect(res.unitDiscount, equals(15000));
      expect(res.totalDiscount, equals(30000));
      expect(res.subtotal, equals(0));
    });

    test('percentage discount calculation with half-up', () {
      // 25,000 * 10% = 2,500
      final res1 = DiscountCalculator.calculateItemDiscount(
        unitPrice: 25000,
        qty: 2,
        discountValue: 10,
        isPercent: true,
      );
      expect(res1.unitDiscount, equals(2500));
      expect(res1.totalDiscount, equals(5000));
      expect(res1.subtotal, equals(45000));

      // 15 * 50% = 7.5 -> rounds to 8
      final res2 = DiscountCalculator.calculateItemDiscount(
        unitPrice: 15,
        qty: 1,
        discountValue: 50,
        isPercent: true,
      );
      expect(res2.unitDiscount, equals(8));
      expect(res2.totalDiscount, equals(8));
      expect(res2.subtotal, equals(7));
    });

    test('percentage discount 100% and >100% clamped', () {
      final res = DiscountCalculator.calculateItemDiscount(
        unitPrice: 50000,
        qty: 1,
        discountValue: 150, // exceeds 100%
        isPercent: true,
      );
      expect(res.unitDiscount, equals(50000));
      expect(res.subtotal, equals(0));
    });

    test('basis points discount (bps)', () {
      // 100,000 * 1100 bps (11%) = 11,000
      final res = DiscountCalculator.calculateItemDiscount(
        unitPrice: 100000,
        qty: 1,
        discountValue: 1100,
        isPercent: true,
        isBps: true,
      );
      expect(res.unitDiscount, equals(11000));
      expect(res.subtotal, equals(89000));
    });
  });

  group('DiscountCalculator - calculateOverallDiscount', () {
    test('nominal overall discount within bounds', () {
      expect(
        DiscountCalculator.calculateOverallDiscount(
          subtotal: 100000,
          discountValue: 15000,
          isPercent: false,
        ),
        equals(15000),
      );
    });

    test('nominal overall discount capped at subtotal', () {
      expect(
        DiscountCalculator.calculateOverallDiscount(
          subtotal: 50000,
          discountValue: 80000,
          isPercent: false,
        ),
        equals(50000),
      );
    });

    test('percentage overall discount with half-up rounding', () {
      // 75,000 * 15% = 11,250
      expect(
        DiscountCalculator.calculateOverallDiscount(
          subtotal: 75000,
          discountValue: 15,
          isPercent: true,
        ),
        equals(11250),
      );

      // 99 * 50% = 49.5 -> rounds to 50
      expect(
        DiscountCalculator.calculateOverallDiscount(
          subtotal: 99,
          discountValue: 50,
          isPercent: true,
        ),
        equals(50),
      );
    });

    test('zero or negative subtotal returns 0', () {
      expect(
        DiscountCalculator.calculateOverallDiscount(
          subtotal: 0,
          discountValue: 5000,
        ),
        equals(0),
      );
    });
  });

  group('DiscountCalculator - allocateOverallDiscount (Largest Remainder)', () {
    test('sum of allocated shares exactly matches overallDiscount', () {
      // 3 items with subtotals 10000, 20000, 30000 -> total 60000
      // Discount = 7000
      // 7000 * 10/60 = 1166.666 -> 1166 (rem 40000)
      // 7000 * 20/60 = 2333.333 -> 2333 (rem 20000)
      // 7000 * 30/60 = 3500.000 -> 3500 (rem 0)
      // Base shares sum = 1166 + 2333 + 3500 = 6999. Deficit = 1.
      // Item 0 has largest remainder (40000), gets +1 -> 1167.
      final subtotals = [10000, 20000, 30000];
      final shares = DiscountCalculator.allocateOverallDiscount(
        subtotals: subtotals,
        overallDiscount: 7000,
      );

      expect(shares, equals([1167, 2333, 3500]));
      expect(shares.fold<int>(0, (s, e) => s + e), equals(7000));
    });

    test('allocation with equal remainders preserves deterministic ordering', () {
      // 3 items with equal subtotals 10000 each -> total 30000
      // Discount = 1000
      // 1000 / 3 = 333 each (rem 1000 each)
      // Deficit = 1 -> First item gets +1 -> [334, 333, 333]
      final subtotals = [10000, 10000, 10000];
      final shares = DiscountCalculator.allocateOverallDiscount(
        subtotals: subtotals,
        overallDiscount: 1000,
      );

      expect(shares, equals([334, 333, 333]));
      expect(shares.fold<int>(0, (s, e) => s + e), equals(1000));
    });

    test('no share exceeds the item subtotal', () {
      final subtotals = [1000, 50000];
      final shares = DiscountCalculator.allocateOverallDiscount(
        subtotals: subtotals,
        overallDiscount: 51000, // 100% discount
      );
      expect(shares, equals([1000, 50000]));
    });

    test('zero discount yields zero shares', () {
      final shares = DiscountCalculator.allocateOverallDiscount(
        subtotals: [5000, 10000],
        overallDiscount: 0,
      );
      expect(shares, equals([0, 0]));
    });

    test('empty list returns empty', () {
      final shares = DiscountCalculator.allocateOverallDiscount(
        subtotals: [],
        overallDiscount: 5000,
      );
      expect(shares, isEmpty);
    });
  });

  group('DiscountCalculator - calculateCartTotals', () {
    test('exclusive tax with item and overall discount', () {
      // Item 1: 2 x 20,000 = 40,000 gross. Discount 2,000/unit = 4,000. Subtotal = 36,000.
      // Item 2: 1 x 50,000 = 50,000 gross. Discount 0. Subtotal = 50,000.
      // Gross subtotal = 90,000. Items discount = 4,000. Subtotal = 86,000.
      // Overall discount = 6,000. Total discount = 10,000. Net basis = 80,000.
      // Tax: exclusive 11% (1100 bps) of 80,000 = 8,800.
      // Final total = 88,800.
      final result = DiscountCalculator.calculateCartTotals(
        grossPrices: [40000, 50000],
        itemDiscounts: [4000, 0],
        overallDiscountValue: 6000,
        taxRateBps: 1100,
        taxMode: 'exclusive',
        taxEnabled: true,
      );

      expect(result.grossSubtotal, equals(90000));
      expect(result.itemsDiscount, equals(4000));
      expect(result.subtotal, equals(86000));
      expect(result.overallDiscount, equals(6000));
      expect(result.totalDiscount, equals(10000));
      expect(result.netBasis, equals(80000));
      expect(result.tax, equals(8800));
      expect(result.finalTotal, equals(88800));

      // Check allocated shares:
      // Subtotals: [36000, 50000] = 86000
      // 6000 allocated proportionally:
      expect(result.itemDiscountShares.fold<int>(0, (s, e) => s + e), equals(6000));
    });

    test('inclusive tax with item and overall discount', () {
      // Subtotal 100,000 - Overall discount 10,000 = Net basis 90,000 (tax inclusive 11%)
      // Tax = 90,000 * 1100 / (10000 + 1100) = 99,000,000 / 11100 = 8919
      // Final total = 90,000 (inclusive of tax)
      final result = DiscountCalculator.calculateCartTotals(
        grossPrices: [100000],
        itemDiscounts: [0],
        overallDiscountValue: 10000,
        taxRateBps: 1100,
        taxMode: 'inclusive',
        taxEnabled: true,
      );

      expect(result.subtotal, equals(100000));
      expect(result.overallDiscount, equals(10000));
      expect(result.netBasis, equals(90000));
      expect(result.tax, equals(8919));
      expect(result.finalTotal, equals(90000));
    });
  });
}
