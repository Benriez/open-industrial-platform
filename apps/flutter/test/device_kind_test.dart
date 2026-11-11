import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/widgets/device_kind.dart';

/// The vocabulary of the **type of a device**.
///
/// The Core paints the type of a device as the identifier of its own enum
/// (`SingleBoardComputer`, `NetworkDevice`, `IndustrialDevice`). The client
/// needs **one** owner of that vocabulary: every type that the Core can
/// really produce gets a word of the surface, an icon and a category — and a
/// type that the client does not know stays honestly named as unknown
/// instead of falling back silently.
void main() {
  // The types that the enum of the inventory of the Core can deliver.
  const core = ['Server', 'Desktop', 'Laptop', 'SingleBoardComputer',
    'NetworkDevice', 'IndustrialDevice', 'Sensor', 'Other'];

  test('every type that the Core can deliver has a word of the surface', () {
    for (final kind in core) {
      expect(deviceKindLabel(kind), isNotNull, reason: kind);
    }
  });

  test('a type whose identifier is no word is not painted as itself', () {
    // `Server` is a word of the surface; `SingleBoardComputer` is not. The
    // identifier of the Core never reaches the operator as a word.
    for (final kind in [
      'SingleBoardComputer',
      'NetworkDevice',
      'IndustrialDevice',
      'Other'
    ]) {
      expect(deviceKindName(kind), isNot(contains(kind)), reason: kind);
    }
  });

  test('every type that the Core can deliver has an icon of its own', () {
    final icons = core.map(deviceKindIcon).toSet();
    // Not every type needs a distinct icon, but none of them may fall back
    // to the icon of an unknown device.
    for (final kind in core) {
      expect(deviceKindIcon(kind), isNot(Icons.device_unknown_outlined),
          reason: kind);
    }
    expect(icons.length, greaterThan(1));
  });

  test('every type that the Core can deliver has a category', () {
    for (final kind in core) {
      expect(
          ['network', 'industrial', 'observability', 'compute'],
          contains(deviceKindCategory(kind)),
          reason: kind);
    }
  });

  test('the types of the real inventory carry the right category', () {
    expect(deviceKindCategory('NetworkDevice'), 'network');
    expect(deviceKindCategory('network_device'), 'network');
    expect(deviceKindCategory('IndustrialDevice'), 'industrial');
    expect(deviceKindCategory('Sensor'), 'industrial');
    expect(deviceKindCategory('Server'), 'compute');
  });

  test('the spelling of the inventory route names the same type', () {
    expect(deviceKindLabel('network_device'), deviceKindLabel('NetworkDevice'));
    expect(deviceKindLabel('single_board_computer'),
        deviceKindLabel('SingleBoardComputer'));
    expect(deviceKindLabel('industrial_device'),
        deviceKindLabel('IndustrialDevice'));
  });

  test('the vocabulary of the demo of the Core stays known', () {
    for (final kind in ['Compute', 'Edge', 'Mobile', 'Gateway', 'Bridge',
      'Media', 'Industrial', 'Service']) {
      expect(deviceKindLabel(kind), isNotNull, reason: kind);
      expect(deviceKindIcon(kind), isNot(Icons.device_unknown_outlined),
          reason: kind);
    }
  });

  test('a type that the client does not know stays honestly named', () {
    expect(deviceKindLabel('SomethingNew'), isNull);
    expect(deviceKindName('SomethingNew'),
        'Unbekannter Gerätetyp · SomethingNew');
    expect(deviceKindIcon('SomethingNew'), Icons.device_unknown_outlined);
    // An unknown type never borrows the identity of another type.
    expect(deviceKindIcon('SomethingNew'), isNot(deviceKindIcon('Server')));
  });

  test('both spellings of a type carry the same word, icon and category', () {
    // The enum of the Core and the spelling of the inventory route name the
    // **same** type: the vocabulary knows one type, not two.
    for (final pair in [
      ['Server', 'server'],
      ['Desktop', 'desktop'],
      ['Laptop', 'laptop'],
      ['SingleBoardComputer', 'single_board_computer'],
      ['NetworkDevice', 'network_device'],
      ['IndustrialDevice', 'industrial_device'],
      ['Sensor', 'sensor'],
      ['Other', 'other'],
    ]) {
      expect(deviceKindLabel(pair[0]), deviceKindLabel(pair[1]),
          reason: pair[1]);
      expect(deviceKindIcon(pair[0]), deviceKindIcon(pair[1]),
          reason: pair[1]);
      expect(deviceKindCategory(pair[0]), deviceKindCategory(pair[1]),
          reason: pair[1]);
    }
  });
}
