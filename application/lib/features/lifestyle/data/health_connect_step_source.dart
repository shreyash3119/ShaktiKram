import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'step_source.dart';

/// Reads steps from Android Health Connect with the `health` package. Read only: it never writes to Health Connect.
/// This is the only file that imports the plugin.
class HealthConnectStepSource implements StepSource {
  final Health _health = Health();
  bool _configured = false;

  static const _types = [HealthDataType.STEPS];
  static const _access = [HealthDataAccess.READ];

  Future<void> _ensure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<StepSourceStatus> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) return StepSourceStatus.unsupported;
    await _ensure();
    final sdk = await _health.getHealthConnectSdkStatus();
    if (sdk != HealthConnectSdkStatus.sdkAvailable) return StepSourceStatus.notInstalled;
    final granted = await _health.hasPermissions(_types, permissions: _access);
    return granted == true ? StepSourceStatus.ready : StepSourceStatus.needsAccess;
  }

  @override
  Future<bool> requestAccess() async {
    await _ensure();
    return _health.requestAuthorization(_types, permissions: _access);
  }

  @override
  Future<void> openInstallPage() async {
    await _ensure();
    await _health.installHealthConnect();
  }

  @override
  Future<int?> totalSteps(DateTime from, DateTime to) async {
    await _ensure();
    return _health.getTotalStepsInInterval(from, to);
  }
}
