import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/oip_strings.dart';
import '../models/infrastructure.dart';
import '../models/opcua_setup.dart';
import '../services/api.dart';
import '../services/local_file_picker_stub.dart'
    if (dart.library.html) '../services/local_file_picker_web.dart';
import '../services/local_text_download_stub.dart'
    if (dart.library.html) '../services/local_text_download_web.dart';

class OpcuaSetupDialog extends StatefulWidget {
  const OpcuaSetupDialog(this.api, this.infrastructure, {super.key});
  final OpcuaSetupApi api;
  final InfrastructureContext infrastructure;

  @override
  State<OpcuaSetupDialog> createState() => _OpcuaSetupDialogState();
}

class _PointInput {
  final metric = TextEditingController();
  final node = TextEditingController();
  OpcuaPointKind kind = OpcuaPointKind.float;

  void dispose() {
    metric.dispose();
    node.dispose();
  }
}

class _OpcuaSetupDialogState extends State<OpcuaSetupDialog> {
  final endpoint = TextEditingController();
  final serverUri = TextEditingController();
  final namespace = TextEditingController();
  final seconds = TextEditingController(text: '10');
  final certificate = TextEditingController();
  final fingerprint = TextEditingController();
  final points = [_PointInput()];
  final form = GlobalKey<FormState>();
  InventoryDevice? device;
  OpcuaSetupResult? result;
  OpcuaConfigured? configured;
  String? error;
  bool busy = false;
  bool replacing = false;
  String? changedSource;
  late final String originalScope;

  @override
  void initState() {
    super.initState();
    originalScope = widget.infrastructure.scopeSignature;
    widget.infrastructure.addListener(_checkScope);
  }

  void _checkScope() {
    if (widget.infrastructure.scopeSignature != originalScope && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.infrastructure.removeListener(_checkScope);
    for (final controller in [
      endpoint,
      serverUri,
      namespace,
      seconds,
      certificate,
      fingerprint,
    ]) {
      controller.dispose();
    }
    for (final point in points) {
      point.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<OpcuaSetupResult> Function() action,
      {bool save = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await action();
      if (!mounted) return;
      setState(() {
        result = response;
        if (response is OpcuaConfigured) {
          configured = response;
          replacing = false;
          if (save) changedSource = response.source;
        }
      });
    } catch (failure) {
      if (mounted) setState(() => error = _error(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _error(Object failure) =>
      context.tr(switch (failure is ApiFailure ? failure.code : null) {
        'OPCUA_SETUP_DENIED' =>
          'Dieses Gerät ist für die OPC-UA-Einrichtung nicht freigegeben. Prüfen Sie Standort, Rechte und vorhandene Quellen.',
        'OPCUA_SETUP_DISABLED' =>
          'Für dieses OIP ist bereits ein lokales OPC-UA-Profil eingerichtet oder die Instanz läuft im Wiederherstellungsmodus.',
        'OPCUA_SETUP_ENDPOINT' =>
          'Geben Sie eine OPC-UA-Adresse mit IP und Port ein.',
        'OPCUA_SETUP_CONFIGURATION' =>
          'Prüfen Sie die Anwendungs-URI, den Namensraum und die eindeutigen Datenpunkte.',
        'OPCUA_CERT_INVALID' =>
          'Fügen Sie genau ein gültiges, selbstsigniertes RSA-Serverzertifikat im PEM-Format ein.',
        'OPCUA_CERT_TIME' =>
          'Das Serverzertifikat ist abgelaufen oder noch nicht gültig. Lassen Sie es vom Betreiber erneuern.',
        'OPCUA_CERT_IDENTITY' =>
          'IP-Adresse oder Anwendungs-URI stimmen mit dem Zertifikat nicht überein. Prüfen Sie die Angaben beim Betreiber.',
        'OPCUA_FINGERPRINT_MISMATCH' =>
          'Der geprüfte Fingerabdruck stimmt nicht überein. Klären Sie die Abweichung mit dem Betreiber.',
        'OPCUA_CONFIRMATION_INVALID' =>
          'Die Freigabe ist abgelaufen oder wurde geändert. Öffnen Sie die Zertifikatsprüfung erneut.',
        'OPCUA_SETUP_STORAGE' =>
          'OIP konnte die Einrichtung nicht sicher speichern oder lesen. Prüfen Sie den lokalen Speicher.',
        _ => 'Die OPC-UA-Einrichtung ist gerade nicht verfügbar.',
      });

  Widget _input(String label, TextEditingController controller,
      {String? hint,
      int lines = 1,
      int? limit,
      String? Function(String?)? validate}) {
    return TextFormField(
      controller: controller,
      enabled: !busy,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 2,
      maxLength: limit,
      decoration: InputDecoration(
        labelText: context.tr(label),
        hintText: hint,
        counterText: '',
      ),
      validator: validate ??
          (value) => (value?.trim().isEmpty ?? true)
              ? context.tr('Pflichtfeld')
              : null,
    );
  }

  Future<void> _choose(InventoryDevice? selected) async {
    setState(() {
      device = selected;
      result = null;
      configured = null;
      replacing = false;
      certificate.clear();
      fingerprint.clear();
    });
    if (selected != null) {
      await _run(
          () => widget.api.opcuaSetupStatus(selected.siteId, selected.id));
    }
  }

  Future<void> _selectCertificateFile() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await pickLocalFile('.pem,.crt,.cer,.der', 12000);
      if (bytes == null || !mounted) return;
      if (bytes.isEmpty) throw const FormatException();
      if (bytes.first == 0x30) {
        final encoded = base64.encode(bytes);
        final lines = RegExp('.{1,64}')
            .allMatches(encoded)
            .map((match) => match.group(0)!);
        certificate.text = [
          '-----BEGIN CERTIFICATE-----',
          ...lines,
          '-----END CERTIFICATE-----',
        ].join('\n');
      } else {
        certificate.text = utf8.decode(bytes).trim();
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = context.tr(
            'Die Zertifikatsdatei konnte nicht gelesen werden. Wählen Sie ein einzelnes PEM- oder DER-Zertifikat.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _preview() async {
    if (!form.currentState!.validate()) return;
    final selected = device!;
    fingerprint.clear();
    await _run(() => widget.api.previewOpcuaSetup(
          selected.siteId,
          selected.id,
          replacing
              ? null
              : OpcuaSourceConfiguration(
                  endpoint.text.trim(),
                  serverUri.text.trim(),
                  namespace.text.trim(),
                  int.parse(seconds.text.trim()),
                  points
                      .map((p) => OpcuaSetupPoint(
                          p.metric.text.trim(), p.node.text.trim(), p.kind))
                      .toList(),
                ),
          certificate.text.trim(),
        ));
  }

  Future<void> _approve(OpcuaCertificatePreview preview) async {
    if (!form.currentState!.validate()) return;
    final selected = device!;
    await _run(
        () => widget.api.applyOpcuaSetup(
              selected.siteId,
              selected.id,
              preview.confirmation,
              fingerprint.text.trim(),
            ),
        save: true);
  }

  List<Widget> _connectionFields() {
    return [
      Text(context.tr(
          'Lesend über SignAndEncrypt (Basic256Sha256). Verwenden Sie einen vom Anlagenbetreiber freigegebenen Server mit anonymem Lesezugang.')),
      _input('OPC-UA-Adresse', endpoint,
          hint: 'opc.tcp://192.0.2.10:4840', limit: 512),
      _input('Server-Anwendungs-URI', serverUri,
          hint: 'urn:example:machine', limit: 512),
      _input('Namensraum-URI', namespace,
          hint: 'urn:example:signals', limit: 512),
      _input('Abfrageintervall in Sekunden', seconds, hint: '5–60', limit: 2,
          validate: (value) {
        final interval = int.tryParse(value?.trim() ?? '');
        return interval != null && interval >= 5 && interval <= 60
            ? null
            : context.tr('Geben Sie 5 bis 60 Sekunden ein.');
      }),
      for (final (index, point) in points.indexed) ...[
        _input('Datenpunkt-Bezeichner', point.metric,
            hint: 'temperature', limit: 128),
        _input('Node-Kennung ohne Namensraumindex', point.node,
            hint: 's=Temperature', limit: 256),
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<OpcuaPointKind>(
            key: ObjectKey(point),
            value: point.kind,
            decoration: InputDecoration(labelText: context.tr('Datentyp')),
            items: [
              for (final kind in OpcuaPointKind.values)
                DropdownMenuItem(
                    value: kind,
                    child: Text(context.tr(switch (kind) {
                      OpcuaPointKind.float => 'Gleitkommazahl',
                      OpcuaPointKind.signedInteger => 'Ganzzahl mit Vorzeichen',
                      OpcuaPointKind.unsignedInteger =>
                        'Ganzzahl ohne Vorzeichen',
                      OpcuaPointKind.boolean => 'Wahrheitswert',
                      OpcuaPointKind.text => 'Text',
                    }))),
            ],
            onChanged: busy ? null : (kind) => point.kind = kind!,
          )),
          if (points.length > 1)
            IconButton(
              tooltip: context.tr('Datenpunkt entfernen'),
              onPressed: busy
                  ? null
                  : () {
                      setState(() => points.removeAt(index));
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => point.dispose());
                    },
              icon: const Icon(Icons.remove_circle_outline),
            ),
        ]),
      ],
      if (points.length < 16)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  busy ? null : () => setState(() => points.add(_PointInput())),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Datenpunkt hinzufügen')),
            )),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final infrastructure = widget.infrastructure;
    final devices = (infrastructure.inventory ?? const <InventoryDevice>[])
        .where((row) =>
            row.registration == 'registered' &&
            (row.sourceIds.isEmpty ||
                row.sourceIds.contains('managed-opcua')) &&
            infrastructure.selection.matches(
              organizationId: row.organizationId,
              infrastructureId: row.infrastructureId,
              siteId: row.siteId,
              sourceId: infrastructure.selection.sourceId == null
                  ? null
                  : row.sourceIds
                      .where((id) => id == infrastructure.selection.sourceId)
                      .firstOrNull,
            ))
        .toList();
    final preview = result is OpcuaCertificatePreview
        ? result as OpcuaCertificatePreview
        : null;
    final saved = configured;
    final showForm = result is OpcuaUnconfigured || replacing;
    return AlertDialog(
      title: Text(context.tr('OPC-UA-Quelle einrichten')),
      content: SizedBox(
        width: 568,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (devices.isEmpty)
                  Text(context.tr(
                      'Registrieren Sie ein Gerät unter Geräte & Dienste und wählen Sie seinen Standort im Arbeitsbereich aus.')),
                if (devices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: device?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: context.tr('Gerät und Standort')),
                    items: [
                      for (final row in devices)
                        DropdownMenuItem(
                          value: row.id,
                          child: Text(
                            '${row.name} · ${infrastructure.hierarchy.infrastructureName(row.infrastructureId)} / ${infrastructure.hierarchy.siteName(row.siteId)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (id) {
                            _choose(devices
                                .where((row) => row.id == id)
                                .firstOrNull);
                          },
                  ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(preview.configuration.endpoint),
                  SelectableText(preview.subject),
                  Text(context.tr('Gültig bis {0}', [preview.validUntil])),
                  if (preview.previousSha256 != null)
                    SelectableText(context.tr(
                        'Bisheriger SHA-256-Fingerabdruck: {0}',
                        [preview.previousSha256])),
                  SelectableText(context.tr('Neuer SHA-256-Fingerabdruck: {0}',
                      [preview.fingerprint])),
                  const SizedBox(height: 12),
                  Text(context.tr(
                      'Fordern Sie den Fingerabdruck separat beim Anlagenbetreiber an. Geben Sie ihn hier ein, um genau dieses Zertifikat freizugeben.')),
                  _input(
                      'Unabhängig geprüfter SHA-256-Fingerabdruck', fingerprint,
                      limit: 95),
                ] else if (showForm) ...[
                  const SizedBox(height: 12),
                  if (!replacing) ..._connectionFields(),
                  if (canPickLocalFile)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : _selectCertificateFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(context.tr('Zertifikatsdatei auswählen')),
                      ),
                    ),
                  _input('Serverzertifikat (PEM)', certificate,
                      lines: 4, limit: 16384),
                ] else if (saved != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(saved.configuration.endpoint),
                  SelectableText(context.tr(
                      'Freigegebener SHA-256-Fingerabdruck: {0}',
                      [saved.serverSha256])),
                  const SizedBox(height: 12),
                  Text(context.tr(saved.enabled
                      ? 'Die Einrichtung ist gespeichert. Wenn der Server das OIP-Clientzertifikat noch nicht kennt, lassen Sie es dort vom Betreiber freigeben.'
                      : 'Die Datenerfassung ist in dieser Instanz gesperrt.')),
                  if (canPickLocalFile)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.download),
                        label: Text(context
                            .tr('Öffentliches Clientzertifikat speichern')),
                        onPressed: () => downloadLocalText(
                          'oip-opcua-client.pem',
                          saved.clientCertificate,
                          'application/x-pem-file',
                        ),
                      ),
                    ),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: Text(context
                            .tr('Öffentliches Clientzertifikat kopieren')),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: saved.clientCertificate));
                          if (!context.mounted) return;
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                  content: Text(context
                                      .tr('Clientzertifikat kopiert.'))));
                        },
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              busy ? null : () => Navigator.of(context).pop(changedSource),
          child: Text(context.tr('Schließen')),
        ),
        if (preview != null || replacing)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      error = null;
                      if (preview != null) {
                        result = saved ?? const OpcuaUnconfigured();
                      } else {
                        replacing = false;
                      }
                    }),
            child: Text(context.tr('Zurück')),
          ),
        if (preview != null)
          FilledButton(
            onPressed: busy ? null : () => _approve(preview),
            child: Text(context.tr('Zertifikat freigeben')),
          )
        else if (showForm)
          FilledButton(
            onPressed: busy ? null : _preview,
            child: Text(context.tr('Zertifikat prüfen')),
          )
        else if (saved?.enabled == true)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      replacing = true;
                      certificate.clear();
                    }),
            child: Text(context.tr('Serverzertifikat ersetzen')),
          ),
      ],
    );
  }
}
