import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService extends GetxService {
  static DeviceIdService get to => Get.find<DeviceIdService>();

  static const String _deviceIdKey = 'app_device_id';
  late final String _deviceId;

  String get deviceId => _deviceId;

  Future<DeviceIdService> init() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString(_deviceIdKey);

    if (storedId == null || storedId.trim().isEmpty) {
      storedId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, storedId);
    }

    _deviceId = storedId;
    return this;
  }
}

