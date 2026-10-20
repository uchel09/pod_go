const bool kSimulationMode = true;
const String kAppName = 'POS Me';
const int kFreeProductLimit = 10;

// Harga Paket Simulasi (Rupiah integer)
const int kPriceSemiMonthly = 49000;
const int kPriceSemiYearly = 490000; // Diskon ~2 bulan
const int kPricePremiumMonthly = 99000;
const int kPricePremiumYearly = 990000; // Diskon ~2 bulan

class AppConfig {
  AppConfig._();

  static const bool simulationMode = kSimulationMode;
  static const String appName = kAppName;
  static const int freeProductLimit = kFreeProductLimit;

  static const int priceSemiMonthly = kPriceSemiMonthly;
  static const int priceSemiYearly = kPriceSemiYearly;
  static const int pricePremiumMonthly = kPricePremiumMonthly;
  static const int pricePremiumYearly = kPricePremiumYearly;
}
