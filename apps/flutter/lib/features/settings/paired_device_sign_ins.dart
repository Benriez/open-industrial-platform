import 'package:flutter/material.dart';

import '../../l10n/oip_strings.dart';
import '../../services/api.dart';
import '../../widgets/workstation.dart';

class PairedDeviceSignIns extends StatefulWidget {
  final PairedDeviceManagementApi api;
  final VoidCallback onCurrentRevoked;

  const PairedDeviceSignIns({
    super.key,
    required this.api,
    required this.onCurrentRevoked,
  });

  @override
  State<PairedDeviceSignIns> createState() => _PairedDeviceSignInsState();
}

class _PairedDeviceSignInsState extends State<PairedDeviceSignIns> {
  List<PairedDeviceSignIn>? devices;
  bool busy = true;
  String? feedback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _label(PairedDeviceSignIn device) =>
      device.label ?? context.tr('Mac · {0}', [device.id.substring(0, 8)]);

  Future<void> _load() async {
    try {
      final result = await widget.api.pairedDeviceSignIns();
      if (mounted) setState(() => devices = result);
    } catch (_) {
      if (mounted) {
        setState(
            () => feedback = 'Geräteanmeldungen konnten nicht geladen werden.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _rename(PairedDeviceSignIn device) async {
    var name = device.label ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Geräteanmeldung benennen')),
        content: TextFormField(
          key: const Key('sign-in-device-name'),
          initialValue: name,
          onChanged: (value) => name = value,
          decoration: InputDecoration(labelText: context.tr('Name')),
          maxLength: 64,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Abbrechen')),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: Text(context.tr('Speichern')),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    setState(() {
      feedback = null;
      busy = true;
    });
    try {
      await widget.api.renameDeviceSignIn(device.id, value);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          feedback = 'Der Name konnte nicht gespeichert werden.';
        });
      }
    }
  }

  Future<void> _revoke(PairedDeviceSignIn device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Anmeldung für {0} sperren?', [_label(device)])),
        content: Text(context.tr(device.current
            ? 'Du wirst sofort abgemeldet. Für eine erneute Einrichtung brauchst du einen Einmalcode.'
            : 'Dieses Gerät wird abgemeldet. Für eine erneute Einrichtung braucht es einen Einmalcode.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Abbrechen')),
          ),
          FilledButton(
            key: const Key('confirm-revoke-device-sign-in'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Anmeldung sperren')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      feedback = null;
      busy = true;
    });
    try {
      final current = await widget.api.revokeDeviceSignIn(device.id);
      if (!mounted) return;
      setState(() {
        devices = devices?.where((item) => item.id != device.id).toList();
        busy = false;
        feedback = 'Die Geräteanmeldung wurde gesperrt.';
      });
      if (current) widget.onCurrentRevoked();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          feedback =
              'Der Core konnte die Sperre nicht bestätigen. Versuche es erneut.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Gespeicherte Geräteanmeldungen'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(context.tr(
              'Hier verwaltest du Macs, die sich mit Touch ID bei diesem Core anmelden dürfen.')),
          Text(context.tr(
              'Zum Ersetzen sperrst du die bisherige Anmeldung und richtest Touch ID mit einem neuen Einmalcode wieder ein.')),
          if (busy) const LinearProgressIndicator(),
          if (devices?.isEmpty ?? false)
            Text(context.tr(
                'Für dein Konto sind keine Geräteanmeldungen gespeichert.')),
          for (final device in devices ?? const <PairedDeviceSignIn>[])
            ListTile(
              key: ValueKey(device.id),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.laptop_mac_outlined),
              title: Text(_label(device)),
              subtitle:
                  device.current ? Text(context.tr('Diese Anmeldung')) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: busy ? null : () => _rename(device),
                    tooltip: context.tr('Geräteanmeldung benennen'),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: busy ? null : () => _revoke(device),
                    tooltip: context.tr('Anmeldung sperren'),
                    icon: const Icon(Icons.block_outlined),
                  ),
                ],
              ),
            ),
          if (feedback != null)
            Semantics(liveRegion: true, child: Text(context.tr(feedback!))),
          if (!busy && devices == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    busy = true;
                    feedback = null;
                  });
                  _load();
                },
                child: Text(context.tr('Erneut versuchen')),
              ),
            ),
          const Hairline(),
        ],
      );
}
