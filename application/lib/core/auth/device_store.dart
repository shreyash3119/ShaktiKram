import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small local facts about this device. Used so the app opens offline without asking the server.
abstract class DeviceStore {
  Future<String?> deviceId();
  Future<void> saveDeviceId(String id);
  Future<String?> label();
  Future<void> saveLabel(String label);

  /// True once this device has been registered with the server for the current sign-in.
  Future<bool> registered();
  Future<void> setRegistered(bool value);
}

class SharedPrefsDeviceStore implements DeviceStore {
  SharedPrefsDeviceStore(this._prefs);

  final SharedPreferences _prefs;

  static const _idKey = 'device_id';
  static const _labelKey = 'device_label';
  static const _registeredKey = 'device_registered';

  @override
  Future<String?> deviceId() async => _prefs.getString(_idKey);

  @override
  Future<void> saveDeviceId(String id) async {
    await _prefs.setString(_idKey, id);
  }

  @override
  Future<String?> label() async => _prefs.getString(_labelKey);

  @override
  Future<void> saveLabel(String label) async {
    await _prefs.setString(_labelKey, label);
  }

  @override
  Future<bool> registered() async => _prefs.getBool(_registeredKey) ?? false;

  @override
  Future<void> setRegistered(bool value) async {
    await _prefs.setBool(_registeredKey, value);
  }
}

/// Replaced in `main.dart` (and in tests).
final deviceStoreProvider = Provider<DeviceStore>((ref) {
  throw UnimplementedError('deviceStoreProvider must be overridden');
});
