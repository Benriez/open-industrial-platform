import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/infrastructure.dart';
import '../../services/api.dart';
import '../../widgets/components.dart';
import '../../widgets/device_kind.dart';
import '../../widgets/workstation.dart';

/// The administration of a registered device.
///
/// The Core owns the inventory. The update and the archive are authorized
/// writes that carry the revision of the device as their guard: a stale
/// revision is refused, so two operators cannot overwrite each other
/// unnoticed. The surface names the revision it works on and shows the
/// refusal of the Core verbatim instead of a friendly invention.
class DeviceAdministration extends StatefulWidget {
  final InventoryDevice device;
  final DeviceManagementApi? api;
  final VoidCallback onChanged;

  const DeviceAdministration({
    super.key,
    required this.device,
    required this.api,
    required this.onChanged,
  });

  @override
  State<DeviceAdministration> createState() => _DeviceAdministrationState();
}

class _DeviceAdministrationState extends State<DeviceAdministration> {
  /// The device types of the Core that the administration can write.
  ///
  /// The **word** of a type has one owner (`widgets/device_kind.dart`): the
  /// administration names a type the same way as the identity panel, the
  /// filter and the inventory do, and the **value** stays the identifier that
  /// the Core knows.
  static const deviceTypes = <String>[
    'server',
    'desktop',
    'laptop',
    'single_board_computer',
    'network_device',
    'industrial_device',
    'sensor',
    'other',
  ];

  late final TextEditingController _name =
      TextEditingController(text: widget.device.name);
  late final TextEditingController _site =
      TextEditingController(text: widget.device.siteId);
  late String _type = deviceTypes.contains(widget.device.type)
      ? widget.device.type
      : 'other';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _site.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DeviceAdministration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id ||
        oldWidget.device.revision != widget.device.revision) {
      _name.text = widget.device.name;
      _site.text = widget.device.siteId;
      _type = deviceTypes.contains(widget.device.type)
          ? widget.device.type
          : 'other';
      _error = null;
    }
  }

  Future<void> _update() async {
    final api = widget.api;
    if (api == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // An update of a device is a full replacement. The metadata the Core
      // holds is sent back unchanged, so a change of the name never drops a
      // field of the record.
      await api.update({
        'id': widget.device.id,
        'display_name': _name.text.trim(),
        'device_type': _type,
        'site_id': _site.text.trim(),
        'metadata': widget.device.metadata ?? const <String, dynamic>{},
      }, expectedRevision: widget.device.revision);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(error, 'Das Gerät konnte nicht aktualisiert werden.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final archived = widget.device.registration != 'registered';
    return Column(
      key: const Key('device-administration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VERWALTUNG · REVISION ${widget.device.revision}',
            style: WorkstationTokens.eyebrow(context, color: OipTokens.violet)),
        const SizedBox(height: 6),
        if (api == null)
          const InlineNotice(
            'Verwaltung nicht verfügbar',
            'Dieser Client hat keinen autorisierten Management-Adapter. Das Gerät kann hier nicht geändert werden.',
            icon: Icons.lock_outline,
          )
        else if (archived)
          const InlineNotice(
            'Gerät archiviert',
            'Ein archiviertes Gerät sammelt keine Messwerte mehr. Seine Historie bleibt erhalten.',
            icon: Icons.inventory_2_outlined,
          )
        else ...[
          TextField(
            key: const Key('device-administration-name'),
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Anzeigename'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const Key('device-administration-type'),
                value: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gerätetyp'),
                items: [
                  for (final type in deviceTypes)
                    DropdownMenuItem(
                        value: type, child: Text(deviceKindName(type))),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _type = value ?? _type),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('device-administration-site'),
                controller: _site,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Standort (Site)'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(
              key: const Key('device-administration-update'),
              onPressed: _busy ? null : _update,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Änderungen speichern'),
            ),
          ]),
          // The archive is an offline operation of the Core: the managed
          // session refuses it with OFFLINE_ARCHIVE_REQUIRED. The surface
          // names the procedure instead of offering a write that the Core
          // would refuse.
          InlineNotice(
            'Archivierung ist ein Offline-Vorgang',
            'Der Core archiviert nur mit gestopptem Betrieb. Der Datensatz und '
            'seine Historie bleiben erhalten, das Gerät sammelt keine Messwerte '
            'mehr. Der Vorgang läuft mit dem Offline-Plan des Core: '
            'oip-server --config <core.json> --inventory-plan <plan.json>.',
            icon: Icons.inventory_2_outlined,
            color: OipTokens.statusColor(context, 'degraded'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineNotice(
                'Änderung nicht angenommen',
                _error!,
                icon: Icons.error_outline,
                color: OipTokens.statusColor(context, 'degraded'),
              ),
            ),
        ],
      ],
    );
  }
}
