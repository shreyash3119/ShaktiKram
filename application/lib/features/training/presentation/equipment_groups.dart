import 'package:flutter/material.dart';

import '../data/training_models.dart';

/// Equipment groups shown in the equipment picker and used for exercise icons and filters. Equipment stays one list
/// (one table); the group is worked out on the phone from the equipment key, so no schema change is needed.
/// Custom equipment with an unknown key falls into Accessories.
enum EquipmentGroup {
  machines('Machines', Icons.precision_manufacturing_outlined),
  freeWeights('Free weights', Icons.fitness_center),
  accessories('Accessories', Icons.category_outlined),
  bodyweight('Bodyweight', Icons.accessibility_new),
  cardio('Cardio', Icons.monitor_heart_outlined);

  const EquipmentGroup(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _freeWeightKeys = {'barbell', 'dumbbell', 'ez_bar', 'kettlebell', 'weight_plates', 'plates'};
const _bodyweightKeys = {'pull_up_bar', 'dip_station', 'bodyweight'};
const _cardioKeys = {'treadmill', 'stationary_bike', 'stairmaster', 'elliptical', 'rowing_machine'};

EquipmentGroup equipmentGroupOf(String key) {
  if (_cardioKeys.contains(key)) return EquipmentGroup.cardio;
  if (_freeWeightKeys.contains(key)) return EquipmentGroup.freeWeights;
  if (_bodyweightKeys.contains(key)) return EquipmentGroup.bodyweight;
  if (key.endsWith('_machine')) return EquipmentGroup.machines;
  return EquipmentGroup.accessories;
}

/// The icon for an exercise, from its equipment: a pulley for cable work, otherwise the equipment's group.
IconData iconForEquipment(EquipmentRef? e) {
  if (e == null) return Icons.fitness_center;
  if (e.key.startsWith('cable')) return Icons.cable;
  return equipmentGroupOf(e.key).icon;
}
