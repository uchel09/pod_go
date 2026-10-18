/// Tingkatan tier lisensi pada sistem POS Me.
enum Tier {
  free,
  semi,
  premium;

  String get displayName {
    switch (this) {
      case Tier.free:
        return 'Gratis';
      case Tier.semi:
        return 'Semi Premium';
      case Tier.premium:
        return 'Premium';
    }
  }

  static Tier fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'semi':
      case 'semi_premium':
      case 'semipremium':
        return Tier.semi;
      case 'premium':
        return Tier.premium;
      case 'free':
      default:
        return Tier.free;
    }
  }
}

