import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lifestyle_providers.dart';
import 'step_import_service.dart';
import 'step_source.dart';

final stepImportServiceProvider = Provider<StepImportService>((ref) {
  return StepImportService(
    source: ref.read(stepSourceProvider),
    lifestyle: ref.read(lifestyleServiceProvider),
    repository: ref.read(lifestyleRepositoryProvider),
  );
});

enum StepSyncPhase { checking, unsupported, notInstalled, needsAccess, ready, syncing, error }

class StepSyncState {
  const StepSyncState({this.phase = StepSyncPhase.checking, this.lastSyncAt, this.todaySteps, this.keptManualDays = 0, this.message});

  final StepSyncPhase phase;
  final DateTime? lastSyncAt;
  final int? todaySteps;
  final int keptManualDays;
  final String? message;

  StepSyncState copyWith({StepSyncPhase? phase, DateTime? lastSyncAt, int? todaySteps, int? keptManualDays, String? message, bool clearMessage = false}) {
    return StepSyncState(
      phase: phase ?? this.phase,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      todaySteps: todaySteps ?? this.todaySteps,
      keptManualDays: keptManualDays ?? this.keptManualDays,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Owns the phone-steps connection: checking it, asking for access, and importing. Asking for access only ever
/// happens from [connect], which a button calls. [syncIfReady] never shows a prompt.
class StepSyncController extends Notifier<StepSyncState> {
  bool _busy = false;

  @override
  StepSyncState build() => const StepSyncState();

  static StepSyncPhase _phase(StepSourceStatus s) => switch (s) {
        StepSourceStatus.unsupported => StepSyncPhase.unsupported,
        StepSourceStatus.notInstalled => StepSyncPhase.notInstalled,
        StepSourceStatus.needsAccess => StepSyncPhase.needsAccess,
        StepSourceStatus.ready => StepSyncPhase.ready,
      };

  /// Looks at the connection without changing anything.
  Future<void> check() async {
    if (_busy) return;
    try {
      final status = await ref.read(stepSourceProvider).status();
      state = state.copyWith(phase: _phase(status), clearMessage: true);
    } catch (_) {
      state = state.copyWith(phase: StepSyncPhase.error, message: 'Could not check Health Connect.');
    }
  }

  /// The button: install Health Connect, ask for access, then import.
  Future<void> connect() async {
    if (_busy) return;
    final source = ref.read(stepSourceProvider);
    try {
      if (state.phase == StepSyncPhase.notInstalled) {
        await source.openInstallPage();
        return;
      }
      final granted = await source.requestAccess();
      await check();
      if (granted && state.phase == StepSyncPhase.ready) await sync();
    } catch (_) {
      state = state.copyWith(phase: StepSyncPhase.error, message: 'Could not connect to Health Connect.');
    }
  }

  /// Imports now. Does nothing unless access was already granted.
  Future<void> sync() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(phase: StepSyncPhase.syncing, clearMessage: true);
    try {
      final result = await ref.read(stepImportServiceProvider).importRecent();
      state = StepSyncState(phase: StepSyncPhase.ready, lastSyncAt: DateTime.now(), todaySteps: result.todaySteps, keptManualDays: result.daysKeptManual);
    } catch (_) {
      state = state.copyWith(phase: StepSyncPhase.error, message: 'Reading steps failed. Your saved data is unchanged.');
    } finally {
      _busy = false;
    }
  }

  /// For app open, resume and the timer: checks quietly and imports only if already allowed.
  Future<void> syncIfReady() async {
    if (_busy) return;
    try {
      final status = await ref.read(stepSourceProvider).status();
      if (status != StepSourceStatus.ready) {
        state = state.copyWith(phase: _phase(status));
        return;
      }
    } catch (_) {
      return;
    }
    unawaited(sync());
  }
}

final stepSyncProvider = NotifierProvider<StepSyncController, StepSyncState>(StepSyncController.new);
