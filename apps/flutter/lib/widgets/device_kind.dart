/// The vocabulary of the **type of a device**.
///
/// The Core paints the type of a device as the identifier of its own enum
/// (`SingleBoardComputer`, `NetworkDevice`, `IndustrialDevice`), while the
/// demo of the Core uses a different vocabulary (`Compute`, `Gateway`,
/// `Edge`). The client needs **one** owner of that vocabulary: every type
/// that the Core can really produce gets a word of the surface, an icon and
/// a category — and a type that the client does not know stays honestly
/// named as unknown instead of falling back silently.
///
/// The file lives beside the widgets because the icon is a part of the
/// vocabulary: a label and an icon that disagree about a device are two
/// vocabularies.
library;

import 'package:flutter/material.dart';

/// The word of the surface for a type of a device.
///
/// The keys are the identifiers that the Core delivers: the names of the
/// enum of the real inventory, the same names in the spelling of the
/// inventory route (`network_device`) and the words of the demo.
const Map<String, String> _labels = {
  // The types that the inventory of the Core can really deliver.
  'Server': 'Server',
  'Desktop': 'Desktop',
  'Laptop': 'Laptop',
  'SingleBoardComputer': 'Einzelplatine',
  'NetworkDevice': 'Netzwerkgerät',
  'IndustrialDevice': 'Industriegerät',
  'Sensor': 'Sensor',
  'Other': 'Sonstiges Gerät',
  // The same types in the spelling of the inventory route.
  'server': 'Server',
  'desktop': 'Desktop',
  'laptop': 'Laptop',
  'single_board_computer': 'Einzelplatine',
  'network_device': 'Netzwerkgerät',
  'industrial_device': 'Industriegerät',
  'sensor': 'Sensor',
  'other': 'Sonstiges Gerät',
  // The vocabulary of the demo of the Core.
  'Compute': 'Compute',
  'Edge': 'Edge',
  'Mobile': 'Mobile Device',
  'Gateway': 'Router / Gateway',
  'Bridge': 'Bridge',
  'Media': 'Media',
  'Industrial': 'Industriegerät',
  'Service': 'Service',
};

/// The word of the surface for a type of a device, or `null` when the client
/// does not know the type.
String? deviceKindLabel(String kind) => _labels[kind];

/// The word of the surface for a type of a device.
///
/// A type that the client does not know is **named** as unknown and carries
/// the identifier of the Core with it: the surface never shows a raw
/// identifier of the Core as if it were a word of the surface.
String deviceKindName(String kind) =>
    _labels[kind] ?? 'Unbekannter Gerätetyp · $kind';

/// The icon of a type of a device.
///
/// A type that the client does not know gets the icon of an unknown device:
/// the surface says that it does not know the type instead of showing a
/// device of a different kind.
///
/// The two spellings of a type — the enum of the Core and the spelling of
/// the inventory route — carry the **same** icon: the vocabulary knows one
/// type, not two.
IconData deviceKindIcon(String kind) => switch (kind) {
      'Server' || 'server' || 'Compute' || 'Edge' => Icons.dns_outlined,
      'Desktop' || 'desktop' => Icons.desktop_windows_outlined,
      'Laptop' || 'laptop' => Icons.laptop_mac,
      'SingleBoardComputer' || 'single_board_computer' => Icons.memory,
      'NetworkDevice' || 'network_device' || 'Gateway' || 'Bridge' =>
        Icons.router_outlined,
      'IndustrialDevice' || 'industrial_device' || 'Industrial' || 'Sensor' ||
        'sensor' =>
        Icons.sensors,
      'Mobile' => Icons.phone_android_outlined,
      'Media' => Icons.tv,
      'Service' => Icons.storage_outlined,
      'Other' || 'other' => Icons.devices_other,
      _ => Icons.device_unknown_outlined,
    };

/// The category of a type of a device: the tint of the surface follows it.
///
/// The categories are the ones of the design system (`network`,
/// `industrial`, `observability`, `compute`).
String deviceKindCategory(String kind) => switch (kind) {
      'Sensor' || 'sensor' || 'Industrial' || 'IndustrialDevice' ||
        'industrial_device' =>
        'industrial',
      'Gateway' || 'Bridge' || 'Mobile' || 'NetworkDevice' || 'network_device' =>
        'network',
      'Media' => 'observability',
      _ => 'compute',
    };
