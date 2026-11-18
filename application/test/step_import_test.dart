import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/features/lifestyle/data/lifestyle_repository.dart';
import 'package:shaktikram/features/lifestyle/data/lifestyle_service.dart';
import 'package:shaktikram/features/lifestyle/data/step_import_service.dart';
import 'package:shaktikram/features/lifestyle/data/step_providers.dart';
import 'package:shaktikram/features/lifestyle/data/step_source.dart';

import 'support/fake_server.dart';
import 'support/fakes.dart';

// Local time on purpose: the importer works in the phone's calendar days.
final _now = DateTime(2026, 11, 15, 14, 30);

String _d(int daysAgo) => '2026-11-${(15 - daysAgo).toString().padLeft(2, '0')}';

class _FakeSource implements StepSource {
  _FakeSource({this.state = StepSourceStatus.ready});

  StepSourceStatus state;
  bool grantOnRequest = true;
  final Map<String, int> byDay = {};
  final List<(DateTime, DateTime)> asked = [];

  @override
  Future<StepSourceStatus> status() async => state;

  @override
  Future<bool> requestAccess() async {
    if (grantOnRequest) state = StepSourceStatus.ready;
    return grantOnRequest;
  }

  @override
  Future<void> openInstallPage() async {}

  @override
  Future<int?> totalSteps(DateTime from, DateTime to) async {
    asked.add((from, to));
    final key = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    return byDay[key];
  }
}

class _World {
  _World(this.source) {
    server = FakeServer();
    harness = Harness.ready();
    container = ProviderContainer(overrides: [...harness.overridesWith(server), stepSourceProvider.overrideWithValue(source)]);
  }

  final _FakeSource source;
  late final FakeServer server;
  late final Harness harness;
  late final ProviderContainer container;

  LifestyleRepository get repo => LifestyleRepository(harness.local);
  late final LifestyleService lifestyle = LifestyleService(writer: container.read(changeWriterProvider), repository: repo, clock: () => _now);
  late final StepImportService importer = StepImportService(source: source, lifestyle: lifestyle, repository: repo, clock: () => _now);

  Future<void> start() async {
    await server.registerDevice(id: 'device-1', label: 'Test phone', platform: 'mobile');
    container.read(sessionControllerProvider);
    await pumpEventQueue();
    expect(container.read(sessionControllerProvider).phase, SessionPhase.ready);
  }

  Future<void> sync() => container.read(syncStatusProvider.notifier).syncNow();
}

Future<_World> _ready(_FakeSource source) async {
  final w = _World(source);
  addTearDown(w.container.dispose);
  await w.start();
  return w;
}

void main() {
  test('seven days are read, today only up to now, and saved as imported', () async {
    final src = _FakeSource()..byDay.addAll({_d(0): 4200, _d(1): 9000, _d(3): 12000});
    final w = await _ready(src);

    final r = await w.importer.importRecent();
    expect((r.daysChecked, r.daysWritten, r.todaySteps), (3, 3, 4200));
    expect(src.asked.first.$2, _now, reason: 'today is read from midnight to now');
    expect(src.asked[1].$2, DateTime(2026, 11, 15), reason: 'yesterday ends at midnight');

    final today = (await w.repo.stepsFor(_d(0)))!;
    expect((today.steps, today.source), (4200, 'device_import'));
    expect((await w.repo.stepsFor(_d(3)))!.steps, 12000);
    expect(await w.repo.stepsFor(_d(2)), isNull, reason: 'no data and no zero rows');

    await w.sync();
    expect(w.server.tables['daily_steps']!.length, 3);
  });

  test('an imported day is updated when the total changes and left alone when it does not', () async {
    final src = _FakeSource()..byDay[_d(0)] = 3000;
    final w = await _ready(src);
    await w.importer.importRecent();
    await w.sync();
    final rev = w.server.revision;

    expect((await w.importer.importRecent()).daysWritten, 0);
    await w.sync();
    expect(w.server.revision, rev, reason: 'nothing was written, so nothing was sent');

    src.byDay[_d(0)] = 5500;
    expect((await w.importer.importRecent()).daysWritten, 1);
    expect((await w.repo.stepsFor(_d(0)))!.steps, 5500);
    await w.sync();
    expect(w.server.tables['daily_steps']!.length, 1, reason: 'the same record is edited');
  });

  test('a day entered by hand is never overwritten', () async {
    final src = _FakeSource()..byDay.addAll({_d(0): 8000, _d(1): 7000});
    final w = await _ready(src);
    await w.lifestyle.setSteps(6500, localDate: _d(1));

    final r = await w.importer.importRecent();
    expect((r.daysWritten, r.daysKeptManual), (1, 1));
    final day = (await w.repo.stepsFor(_d(1)))!;
    expect((day.steps, day.source), (6500, 'manual'));
  });

  test('typing a day over an imported one locks it from then on', () async {
    final src = _FakeSource()..byDay[_d(0)] = 2000;
    final w = await _ready(src);
    await w.importer.importRecent();
    await w.lifestyle.setSteps(2500, localDate: _d(0));
    src.byDay[_d(0)] = 9000;

    expect((await w.importer.importRecent()).daysKeptManual, 1);
    expect((await w.repo.stepsFor(_d(0)))!.steps, 2500);
  });

  test('connect asks for access once, then imports; sync without access reads nothing', () async {
    final src = _FakeSource(state: StepSourceStatus.needsAccess)..byDay[_d(0)] = 1234;
    final w = await _ready(src);
    final c = w.container.read(stepSyncProvider.notifier);

    await c.syncIfReady();
    expect(w.container.read(stepSyncProvider).phase, StepSyncPhase.needsAccess);
    expect(src.asked, isEmpty, reason: 'no prompt and no reading without access');

    await c.connect();
    expect(w.container.read(stepSyncProvider).phase, StepSyncPhase.ready);
    expect((await w.repo.stepsFor(_d(0)))?.steps, isNotNull);
  });

  test('refused access stays at needs-access and writes nothing', () async {
    final src = _FakeSource(state: StepSourceStatus.needsAccess)
      ..grantOnRequest = false
      ..byDay[_d(0)] = 1234;
    final w = await _ready(src);
    await w.container.read(stepSyncProvider.notifier).connect();
    expect(w.container.read(stepSyncProvider).phase, StepSyncPhase.needsAccess);
    expect(await w.repo.stepsFor(_d(0)), isNull);
  });
}
