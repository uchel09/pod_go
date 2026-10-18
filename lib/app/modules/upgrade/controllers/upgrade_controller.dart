import 'package:get/get.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/features/tier_enum.dart';
import '../../../core/services/feature_gate.dart';

class UpgradeController extends GetxController {
  final FeatureGate _featureGate = FeatureGate.to;

  Rx<Tier> get currentTier => _featureGate.tier;

  Feature? get requestedFeature =>
      Get.arguments is Map ? Get.arguments['feature'] as Feature? : null;
}
