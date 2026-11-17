import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/features/training/data/training_models.dart';
import 'package:shaktikram/features/training/presentation/equipment_groups.dart';

EquipmentRef _e(String key) => EquipmentRef(id: key, key: key, label: key);

void main() {
  test('equipment keys fall into the groups from the requirements', () {
    expect(equipmentGroupOf('chest_press_machine'), EquipmentGroup.machines);
    expect(equipmentGroupOf('smith_machine'), EquipmentGroup.machines);
    expect(equipmentGroupOf('dumbbell'), EquipmentGroup.freeWeights);
    expect(equipmentGroupOf('ez_bar'), EquipmentGroup.freeWeights);
    expect(equipmentGroupOf('resistance_bands'), EquipmentGroup.accessories);
    expect(equipmentGroupOf('pull_up_bar'), EquipmentGroup.bodyweight);
    expect(equipmentGroupOf('treadmill'), EquipmentGroup.cardio);
    expect(equipmentGroupOf('my_custom_thing'), EquipmentGroup.accessories);
  });

  test('exercise icons follow the equipment, cables get a pulley', () {
    expect(iconForEquipment(null), Icons.fitness_center);
    expect(iconForEquipment(_e('cable_machine')), Icons.cable);
    expect(iconForEquipment(_e('bodyweight')), Icons.accessibility_new);
    expect(
      iconForEquipment(_e('leg_press_machine')),
      isNot(iconForEquipment(_e('dumbbell'))),
    );
  });
}
