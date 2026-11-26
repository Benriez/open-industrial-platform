import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/oip_strings.dart';
import '../../models/contracts.dart';

/// A local record of cables confirmed by the person operating the app.
/// The map is device ID → router ID. It carries no measured link state.
class LanWiring {
  static Future<Map<String, String>> load(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final entries = preferences.getStringList(key) ?? const <String>[];
    return {
      for (var i = 0; i + 1 < entries.length; i += 2)
        if (entries[i] != entries[i + 1]) entries[i]: entries[i + 1],
    };
  }

  static Future<bool> save(String key, Map<String, String> links) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setStringList(key, [
      for (final link in links.entries) ...[link.key, link.value]
    ]);
  }
}

class LanWiringDialog extends StatefulWidget {
  const LanWiringDialog({
    super.key,
    required this.routers,
    required this.clients,
    required this.routerLabel,
    required this.links,
  });

  final List<Device> routers;
  final List<Device> Function(Device) clients;
  final String Function(Device) routerLabel;
  final Map<String, String> links;

  @override
  State<LanWiringDialog> createState() => _LanWiringDialogState();
}

class _LanWiringDialogState extends State<LanWiringDialog> {
  Device? _router;
  Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final saved =
        widget.routers.where((router) => widget.links.containsValue(router.id));
    if (saved.length == 1) {
      _choose(saved.single);
    } else if (widget.routers.length == 1) {
      _choose(widget.routers.single);
    }
  }

  void _choose(Device router) {
    _router = router;
    _selected = {
      for (final device in widget.clients(router))
        if (widget.links[device.id] == router.id) device.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    final candidates =
        router == null ? const <Device>[] : widget.clients(router);
    return AlertDialog(
      title: Text(context.tr('LAN-Verkabelung eintragen')),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                  labelText: context.tr('Router'),
                  border: const OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Device>(
                  key: const Key('lan-router-select'),
                  isExpanded: true,
                  value: router,
                  hint: Text(context.tr('Router auswählen')),
                  items: [
                    for (final device in widget.routers)
                      DropdownMenuItem(
                        value: device,
                        child: Text(widget.routerLabel(device),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (device) {
                    if (device != null) setState(() => _choose(device));
                  },
                ),
              ),
            ),
            if (router != null) ...[
              const SizedBox(height: 16),
              Text(context.tr(
                  'Welche Geräte sind direkt per LAN-Kabel mit diesem Router verbunden?')),
              if (candidates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      context.tr('Keine weiteren Geräte an diesem Standort.')),
                ),
              for (final device in candidates)
                CheckboxListTile(
                  key: Key('lan-client-${device.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(device.name),
                  value: _selected.contains(device.id),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(device.id);
                    } else {
                      _selected.remove(device.id);
                    }
                  }),
                ),
            ],
            const SizedBox(height: 8),
            Text(context.tr('Die Verkabelung wird in dieser App gespeichert.')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Abbrechen')),
        ),
        FilledButton(
          key: const Key('lan-wiring-save'),
          onPressed: router == null
              ? null
              : () => Navigator.pop(context, (router.id, _selected)),
          child: Text(context.tr('Verkabelung speichern')),
        ),
      ],
    );
  }
}
