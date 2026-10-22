/// Hasil kalkulasi diskon untuk satu baris item keranjang.
class ItemDiscountResult {
  /// Diskon per unit (Rupiah integer, [0, unitPrice])
  final int unitDiscount;

  /// Total diskon baris = unitDiscount * qty
  final int totalDiscount;

  /// Subtotal baris setelah diskon item = (unitPrice * qty) - totalDiscount
  final int subtotal;

  const ItemDiscountResult({
    required this.unitDiscount,
    required this.totalDiscount,
    required this.subtotal,
  });
}

/// Hasil ringkasan angka transaksi kasir (Single Source of Truth).
class CartTotalsResult {
  /// Total omzet kotor sebelum semua diskon = sum(qty * price)
  final int grossSubtotal;

  /// Total akumulasi diskon per-item = sum(unitDiscount * qty)
  final int itemsDiscount;

  /// Subtotal setelah diskon item = grossSubtotal - itemsDiscount
  final int subtotal;

  /// Nilai diskon total/nota transaksi
  final int overallDiscount;

  /// Total seluruh diskon yang diberikan = itemsDiscount + overallDiscount
  final int totalDiscount;

  /// Dasar pengenaan pajak (Tax Basis) = subtotal - overallDiscount
  final int netBasis;

  /// Nilai pajak (PPN)
  final int tax;

  /// Total akhir transaksi yang wajib dibayar pelanggan
  final int finalTotal;

  /// Porsi alokasi diskon total untuk masing-masing item (Largest Remainder)
  final List<int> itemDiscountShares;

  const CartTotalsResult({
    required this.grossSubtotal,
    required this.itemsDiscount,
    required this.subtotal,
    required this.overallDiscount,
    required this.totalDiscount,
    required this.netBasis,
    required this.tax,
    required this.finalTotal,
    required this.itemDiscountShares,
  });
}

class _RemainderEntry {
  final int index;
  final int remainder;

  const _RemainderEntry({required this.index, required this.remainder});
}

/// Satu-satunya mesin kalkulator diskon murni POS Me (PROMPT 9D).
///
/// Seluruh perhitungan menggunakan integer Rupiah tanpa double untuk mencegah precision loss.
/// Pembulatan persentase menggunakan metode half-up murni:
/// `(numerator + denominator ~/ 2) ~/ denominator`.
class DiscountCalculator {
  DiscountCalculator._();

  /// Pembagian integer dengan pembulatan half-up (mis. 0.5 dibulatkan ke atas).
  static int halfUpDivide(int numerator, int denominator) {
    if (denominator <= 0) return 0;
    if (numerator <= 0) return 0;
    return (numerator + (denominator ~/ 2)) ~/ denominator;
  }

  /// Menghitung diskon item (nominal per unit atau persentase).
  ///
  /// - [unitPrice]: Harga satuan barang (Rupiah integer, >= 0).
  /// - [qty]: Kuantitas barang (>= 1).
  /// - [discountValue]: Nilai diskon yang diinputkan (nominal per unit atau persentase).
  /// - [isPercent]: True jika nilai adalah persen, false jika nominal Rupiah per unit.
  /// - [isBps]: True jika nilai persentase dalam format basis poin (0-10000 bps),
  ///   false jika persen biasa (0-100%).
  static ItemDiscountResult calculateItemDiscount({
    required int unitPrice,
    required int qty,
    required int discountValue,
    bool isPercent = false,
    bool isBps = false,
  }) {
    if (unitPrice <= 0 || qty <= 0 || discountValue <= 0) {
      final gross = (unitPrice > 0 && qty > 0) ? unitPrice * qty : 0;
      return ItemDiscountResult(
        unitDiscount: 0,
        totalDiscount: 0,
        subtotal: gross,
      );
    }

    int unitDisc = 0;
    if (isPercent) {
      final rateBps = isBps
          ? discountValue.clamp(0, 10000)
          : (discountValue.clamp(0, 100)) * 100;
      unitDisc = halfUpDivide(unitPrice * rateBps, 10000);
    } else {
      unitDisc = discountValue;
    }

    final effectiveUnitDiscount = unitDisc.clamp(0, unitPrice);
    final totalDisc = effectiveUnitDiscount * qty;
    final lineSubtotal = (unitPrice * qty) - totalDisc;

    return ItemDiscountResult(
      unitDiscount: effectiveUnitDiscount,
      totalDiscount: totalDisc,
      subtotal: lineSubtotal,
    );
  }

  /// Menghitung diskon total/nota transaksi.
  ///
  /// - [subtotal]: Jumlah subtotal seluruh item setelah diskon per-item (>= 0).
  /// - [discountValue]: Nilai diskon nota yang diinputkan.
  /// - [isPercent]: True jika persentase, false jika nominal Rupiah.
  /// - [isBps]: True jika persentase dalam format basis poin (0-10000 bps).
  static int calculateOverallDiscount({
    required int subtotal,
    required int discountValue,
    bool isPercent = false,
    bool isBps = false,
  }) {
    if (subtotal <= 0 || discountValue <= 0) return 0;

    int disc = 0;
    if (isPercent) {
      final rateBps = isBps
          ? discountValue.clamp(0, 10000)
          : (discountValue.clamp(0, 100)) * 100;
      disc = halfUpDivide(subtotal * rateBps, 10000);
    } else {
      disc = discountValue;
    }

    return disc.clamp(0, subtotal);
  }

  /// Mengalokasikan diskon total ke masing-masing item secara proporsional
  /// menggunakan algoritma **Largest Remainder (Hare-Niemeyer)**.
  ///
  /// Menjamin bahwa `sum(porsi) == overallDiscount` tepat tanpa selisih 1 rupiah,
  /// dan porsi tiap item tidak melebihi subtotal item tersebut.
  static List<int> allocateOverallDiscount({
    required List<int> subtotals,
    required int overallDiscount,
  }) {
    final n = subtotals.length;
    if (n == 0) return const [];
    if (overallDiscount <= 0) return List<int>.filled(n, 0);

    final totalSubtotal = subtotals.fold<int>(0, (sum, s) => sum + (s > 0 ? s : 0));
    if (totalSubtotal <= 0) return List<int>.filled(n, 0);

    final effectiveDiscount = overallDiscount.clamp(0, totalSubtotal);
    if (effectiveDiscount == 0) return List<int>.filled(n, 0);

    if (effectiveDiscount == totalSubtotal) {
      return subtotals.map((s) => s > 0 ? s : 0).toList();
    }

    final baseShares = List<int>.filled(n, 0);
    final remainders = <_RemainderEntry>[];
    int sumBaseShares = 0;

    for (int i = 0; i < n; i++) {
      final s = subtotals[i];
      if (s <= 0) {
        baseShares[i] = 0;
        remainders.add(_RemainderEntry(index: i, remainder: 0));
        continue;
      }
      final numerator = effectiveDiscount * s;
      final base = numerator ~/ totalSubtotal;
      final rem = numerator % totalSubtotal;

      baseShares[i] = base;
      sumBaseShares += base;
      remainders.add(_RemainderEntry(index: i, remainder: rem));
    }

    int deficit = effectiveDiscount - sumBaseShares;
    if (deficit > 0) {
      // Urutkan sisa bagi terbesar terlebih dahulu
      remainders.sort((a, b) {
        final cmp = b.remainder.compareTo(a.remainder);
        if (cmp != 0) return cmp;
        return a.index.compareTo(b.index);
      });

      for (int i = 0; i < deficit && i < remainders.length; i++) {
        final idx = remainders[i].index;
        if (baseShares[idx] < subtotals[idx]) {
          baseShares[idx] += 1;
        }
      }
    }

    return baseShares;
  }

  /// Menghitung seluruh angka transaksi secara terpadu.
  ///
  /// Rumus tunggal:
  /// - subtotal item = qty * harga - diskon item
  /// - subtotal = sum(subtotal item)
  /// - dasar pajak = subtotal - diskon total
  /// - total = dasar pajak + pajak (exclusive) atau dasar pajak (inclusive)
  static CartTotalsResult calculateCartTotals({
    required List<int> grossPrices, // unitPrice * qty per line
    required List<int> itemDiscounts, // total diskon item per line
    required int overallDiscountValue,
    bool isOverallDiscountPercent = false,
    bool isOverallDiscountBps = false,
    int taxRateBps = 0,
    String taxMode = 'exclusive',
    bool taxEnabled = false,
  }) {
    assert(grossPrices.length == itemDiscounts.length);
    final n = grossPrices.length;

    int grossSum = 0;
    int itemsDiscSum = 0;
    final itemSubtotals = List<int>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      final gross = grossPrices[i];
      final disc = itemDiscounts[i].clamp(0, gross);
      final sub = gross - disc;

      grossSum += gross;
      itemsDiscSum += disc;
      itemSubtotals[i] = sub;
    }

    final subtotal = grossSum - itemsDiscSum;

    final overallDisc = calculateOverallDiscount(
      subtotal: subtotal,
      discountValue: overallDiscountValue,
      isPercent: isOverallDiscountPercent,
      isBps: isOverallDiscountBps,
    );

    final totalDisc = itemsDiscSum + overallDisc;
    final netBasis = (subtotal - overallDisc).clamp(0, 999999999999);

    int calculatedTax = 0;
    int finalTotal = netBasis;

    if (taxEnabled && taxRateBps > 0) {
      if (taxMode == 'inclusive') {
        // Harga inklusif: tax = netBasis - round(netBasis * 10000 / (10000 + rateBps))
        final baseBeforeTax = halfUpDivide(netBasis * 10000, 10000 + taxRateBps);
        calculatedTax = (netBasis - baseBeforeTax).clamp(0, netBasis);
        finalTotal = netBasis;
      } else {
        // Eksklusif: tax = round(netBasis * rateBps / 10000), total = netBasis + tax
        calculatedTax = halfUpDivide(netBasis * taxRateBps, 10000);
        finalTotal = netBasis + calculatedTax;
      }
    }

    final shares = allocateOverallDiscount(
      subtotals: itemSubtotals,
      overallDiscount: overallDisc,
    );

    return CartTotalsResult(
      grossSubtotal: grossSum,
      itemsDiscount: itemsDiscSum,
      subtotal: subtotal,
      overallDiscount: overallDisc,
      totalDiscount: totalDisc,
      netBasis: netBasis,
      tax: calculatedTax,
      finalTotal: finalTotal,
      itemDiscountShares: shares,
    );
  }
}

