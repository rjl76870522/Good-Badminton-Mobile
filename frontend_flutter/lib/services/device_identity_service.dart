import 'package:flutter/services.dart';

class DeviceIdentityService {
  const DeviceIdentityService();

  static const MethodChannel _channel =
      MethodChannel('good_badminton/device_identity');

  Future<String?> getStableGuestUserId() async {
    try {
      final value = await _channel.invokeMethod<String>('stableGuestUserId');
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return null;
      if (!RegExp(r'^guest_[a-zA-Z0-9_]+$').hasMatch(normalized)) return null;
      return normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
