import 'contracts.dart';

class HueLight {
  final int id;
  final String name, kind;
  final bool on, reachable;
  final double? brightness, hue, saturation;
  final String? colorMode;
  final int? ct, ctMin, ctMax;

  HueLight.fromJson(Json json)
      : id = json['id'] as int,
        name = (json['name'] as String).trim(),
        kind = json['kind'] as String,
        on = json['on'] as bool,
        reachable = json['reachable'] != false,
        brightness = (json['brightness_percent'] as num?)?.toDouble(),
        hue = (json['hue_degrees'] as num?)?.toDouble(),
        saturation = (json['saturation_percent'] as num?)?.toDouble(),
        colorMode = json['color_mode'] as String?,
        ct = json['ct'] as int?,
        ctMin = (json['ct_range'] as List?)?.first as int?,
        ctMax = (json['ct_range'] as List?)?.last as int?;

  bool get hasColor => hue != null && saturation != null;
  bool get hasWhite => ct != null && ctMin != null && ctMax != null;
}

class HueLights {
  final bool canControl;
  final List<HueLight> lights;

  HueLights.fromJson(Json json)
      : canControl = json['can_control'] as bool,
        lights = (json['lights'] as List)
            .map((item) => HueLight.fromJson(item as Json))
            .toList();
}
