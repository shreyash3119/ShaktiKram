import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the reminder choices are kept. The app uses [SharedPrefsReminderStore]; tests use the in-memory one.
abstract class ReminderStore {
  bool? getBool(String key);
  int? getInt(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
}

class MemoryReminderStore implements ReminderStore {
  final Map<String, Object> _values = {};

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
}

class SharedPrefsReminderStore implements ReminderStore {
  SharedPrefsReminderStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
}

final reminderStoreProvider = Provider<ReminderStore>((ref) => MemoryReminderStore());

/// Which reminders are on, and at what time of day (minutes after midnight, phone time).
class ReminderSettings {
  const ReminderSettings({
    this.workout = true,
    this.leaveForGym = true,
    this.supplements = true,
    this.water = false,
    this.reassessment = true,
    this.workoutMinutes = 18 * 60,
    this.supplementMinutes = 9 * 60,
  });

  final bool workout;
  final bool leaveForGym;
  final bool supplements;
  final bool water;
  final bool reassessment;
  final int workoutMinutes;
  final int supplementMinutes;

  ReminderSettings copyWith({
    bool? workout,
    bool? leaveForGym,
    bool? supplements,
    bool? water,
    bool? reassessment,
    int? workoutMinutes,
    int? supplementMinutes,
  }) => ReminderSettings(
    workout: workout ?? this.workout,
    leaveForGym: leaveForGym ?? this.leaveForGym,
    supplements: supplements ?? this.supplements,
    water: water ?? this.water,
    reassessment: reassessment ?? this.reassessment,
    workoutMinutes: workoutMinutes ?? this.workoutMinutes,
    supplementMinutes: supplementMinutes ?? this.supplementMinutes,
  );

  bool get anyOn => workout || leaveForGym || supplements || water || reassessment;
}

/// The settings keys double as the toggle names used on the Notifications page.
class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  static const kWorkout = 'rem_workout';
  static const kLeave = 'rem_leave';
  static const kSupplements = 'rem_supplements';
  static const kWater = 'rem_water';
  static const kReassess = 'rem_reassess';
  static const kWorkoutTime = 'rem_workout_min';
  static const kSupplementTime = 'rem_supplement_min';

  @override
  ReminderSettings build() {
    final s = ref.read(reminderStoreProvider);
    const d = ReminderSettings();
    return ReminderSettings(
      workout: s.getBool(kWorkout) ?? d.workout,
      leaveForGym: s.getBool(kLeave) ?? d.leaveForGym,
      supplements: s.getBool(kSupplements) ?? d.supplements,
      water: s.getBool(kWater) ?? d.water,
      reassessment: s.getBool(kReassess) ?? d.reassessment,
      workoutMinutes: s.getInt(kWorkoutTime) ?? d.workoutMinutes,
      supplementMinutes: s.getInt(kSupplementTime) ?? d.supplementMinutes,
    );
  }

  ReminderStore get _store => ref.read(reminderStoreProvider);

  void setWorkout(bool v) {
    state = state.copyWith(workout: v);
    _store.setBool(kWorkout, v);
  }

  void setLeaveForGym(bool v) {
    state = state.copyWith(leaveForGym: v);
    _store.setBool(kLeave, v);
  }

  void setSupplements(bool v) {
    state = state.copyWith(supplements: v);
    _store.setBool(kSupplements, v);
  }

  void setWater(bool v) {
    state = state.copyWith(water: v);
    _store.setBool(kWater, v);
  }

  void setReassessment(bool v) {
    state = state.copyWith(reassessment: v);
    _store.setBool(kReassess, v);
  }

  void setWorkoutMinutes(int v) {
    state = state.copyWith(workoutMinutes: v);
    _store.setInt(kWorkoutTime, v);
  }

  void setSupplementMinutes(int v) {
    state = state.copyWith(supplementMinutes: v);
    _store.setInt(kSupplementTime, v);
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(ReminderSettingsNotifier.new);
