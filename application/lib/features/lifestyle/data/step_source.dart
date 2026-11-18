import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a phone step source stands. Nothing is ever read before [ready].
enum StepSourceStatus {
  /// Not Android, or no step source in this build.
  unsupported,

  /// Health Connect is missing or needs an update.
  notInstalled,

  /// Health Connect is there but the owner has not allowed reading steps.
  needsAccess,

  /// Steps can be read.
  ready,
}

/// A place steps can be read from (Health Connect). Kept as an interface so only one file imports the plugin
/// and tests use a fake. Implementations may throw; callers show a plain message.
abstract class StepSource {
  Future<StepSourceStatus> status();

  /// Shows the system permission screen. Returns true when steps can now be read.
  Future<bool> requestAccess();

  /// Opens the store page for Health Connect.
  Future<void> openInstallPage();

  /// Total steps between [from] and [to] (local times), already combined across apps and devices by Health Connect.
  /// Null when the source has no answer.
  Future<int?> totalSteps(DateTime from, DateTime to);
}

/// Used in tests and anywhere no real source is set up.
class UnavailableStepSource implements StepSource {
  const UnavailableStepSource();

  @override
  Future<StepSourceStatus> status() async => StepSourceStatus.unsupported;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<void> openInstallPage() async {}

  @override
  Future<int?> totalSteps(DateTime from, DateTime to) async => null;
}

/// Replaced in `main.dart` with the Health Connect source.
final stepSourceProvider = Provider<StepSource>((ref) => const UnavailableStepSource());
