import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/infrastructure.dart';
import '../../widgets/workstation.dart';

/// The **service registry** of the authorized scope.
///
/// The registry holds what the **operator declared** in the plan of the
/// instance. The Core measures no service: every record carries the provenance
/// `declared`, and the surface says so instead of presenting a declaration as a
/// measurement. A Core that does not deliver the registry at all is named as
/// such — an empty registry would look like a measurement of "no services".
class ServiceRegistryPanel extends StatelessWidget {
  final List<ServiceRecord>? services;
  const ServiceRegistryPanel({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    final registry = services;
    if (registry == null) {
      return const ServiceInventoryMissing();
    }
    if (registry.isEmpty) {
      return WorkstationPanel(
        key: const Key('service-registry-empty'),
        accent: OipTokens.violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SERVICE REGISTRY · AUTHORIZED DATA REQUIRED',
                style: WorkstationTokens.eyebrow(context,
                    color: OipTokens.violet)),
            const SizedBox(height: 10),
            const Text('Keine Dienste deklariert.',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
                'Der Core liefert das Register der Dienste des autorisierten Scopes, '
                'und der Betreiber hat für diesen Scope keinen Dienst deklariert. '
                'Ein leeres Register ist eine Aussage des Betreibers, keine Messung.'),
          ],
        ),
      );
    }
    return WorkstationPanel(
      key: const Key('service-registry'),
      accent: OipTokens.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERVICE REGISTRY · AUTHORIZED DATA REQUIRED',
              style: WorkstationTokens.eyebrow(context, color: OipTokens.violet)),
          const SizedBox(height: 10),
          Text('${registry.length} Dienste deklariert',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
              'Der Core misst keinen Dienst: das Register ist die Deklaration des '
              'Betreibers im Plan der Instanz.'),
          const SizedBox(height: 12),
          for (final service in registry) ...[
            KeyValueGrid(children: [
              KeyValue('SERVICE', '${service.name} · ${service.id}'),
              KeyValue('KIND', service.kind),
              KeyValue('ENDPOINT',
                  service.endpoint == null && service.port == null
                      ? 'Nicht deklariert'
                      : '${service.endpoint ?? '—'}${service.port == null ? '' : ':${service.port}'}'),
              KeyValue('STATE', '${_state(service.state)} · declared'),
              KeyValue('SITE', service.siteId),
              KeyValue('DEVICE',
                  service.deviceIsResolved ? service.deviceId! : 'Nicht zuordenbar'),
            ]),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _state(String state) => switch (state) {
        'running' => 'läuft (deklariert)',
        'stopped' => 'gestoppt (deklariert)',
        _ => 'unbekannt',
      };
}

/// The surface that names the absence of the registry.
///
/// The Core of an instance that does not deliver the registry has **no**
/// service inventory — and the surface says that instead of deriving a service
/// from the name, the kind or the address of a device.
class ServiceInventoryMissing extends StatelessWidget {
  const ServiceInventoryMissing({super.key});

  @override
  Widget build(BuildContext context) => WorkstationPanel(
        key: const Key('service-inventory-missing'),
        accent: OipTokens.violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SERVICE REGISTRY · AUTHORIZED DATA REQUIRED',
                style: WorkstationTokens.eyebrow(context,
                    color: OipTokens.violet)),
            const SizedBox(height: 10),
            Text('Kein autorisiertes Service-Inventar verfügbar.',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Dieser Core liefert kein autorisiertes Service-Register. '
                'Gerätenamen, Device.kind und Registry Connection Type werden nicht '
                'als Dienste ausgegeben.'),
            const SizedBox(height: 14),
            const KeyValueGrid(children: [
              KeyValue('SERVICE REGISTRY QUERY',
                  'Fehlt · Typed Rust Capability erforderlich'),
              KeyValue('DEVICE → SERVICE RELATION',
                  'Fehlt · keine IDs im Device-DTO'),
              KeyValue('ENDPOINT / PROTOCOL', 'Nicht autorisiert geliefert'),
              KeyValue('REST / MCP',
                  'Keine Service-Route bzw. kein Service-Tool vorhanden'),
            ]),
            const SizedBox(height: 10),
            const WorkstationNote(
              'Agent-first Backend-Anforderung',
              'Benötigt werden autorisierte, scoped und paginierte '
              'ServiceDeclaration-DTOs mit Provenance, Freshness und '
              'Device-ID-Beziehung. Der Vertrag: '
              'docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md.',
              icon: Icons.account_tree_outlined,
            ),
          ],
        ),
      );
}
