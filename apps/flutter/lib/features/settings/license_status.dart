import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/oip_strings.dart';
import '../../models/license.dart';
import '../../services/api.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'license_file_stub.dart' if (dart.library.html) 'license_file_web.dart';

class InstallationLicense extends StatefulWidget {
  final LicenseManagementApi api;
  final Future<String?> Function(int maxBytes)? filePicker;

  const InstallationLicense({super.key, required this.api, this.filePicker});

  @override
  State<InstallationLicense> createState() => _InstallationLicenseState();
}

class _InstallationLicenseState extends State<InstallationLicense> {
  static const _maxProofBytes = 8192;
  static const _tooLarge = 'Die Lizenzdatei darf höchstens 8 KB groß sein.';
  final _draft = TextEditingController();
  LicenseStatus? _status;
  LicensePreview? _preview;
  bool _visible = false;
  bool _busy = false;
  bool _editing = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  bool _denied(Object error) =>
      error is ApiFailure && const {401, 403, 404}.contains(error.statusCode);

  Future<void> _refresh({String? feedback}) async {
    setState(() => _busy = true);
    try {
      final status = await widget.api.licenseStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _visible = true;
        _feedback = feedback;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _editing = false;
        _preview = null;
        _draft.clear();
        if (_denied(error)) _visible = false;
        _feedback = 'Lizenzstatus konnte nicht geladen werden.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(bool editing) {
    setState(() {
      _draft.clear();
      _preview = null;
      _feedback = null;
      _editing = editing;
    });
  }

  Future<void> _selectFile() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final text = await (widget.filePicker ?? pickLicenseFile)(_maxProofBytes);
      if (mounted && text != null) await _review(text);
    } on RangeError {
      if (mounted) setState(() => _feedback = _tooLarge);
    } catch (_) {
      if (mounted) {
        setState(
            () => _feedback = 'Die Lizenzdatei konnte nicht gelesen werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review([String? fileContents]) async {
    final raw = fileContents ?? _draft.text;
    if (raw.length > _maxProofBytes ||
        utf8.encode(raw).length > _maxProofBytes) {
      setState(() => _feedback = _tooLarge);
      return;
    }
    if (raw.trim().isEmpty) {
      setState(() => _feedback = fileContents == null
          ? 'Füge einen gültigen JSON-Lizenznachweis ein.'
          : 'Die ausgewählte Datei enthält keinen gültigen JSON-Lizenznachweis.');
      return;
    }

    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final preview = await widget.api.previewLicense(LicenseProof(raw));
      if (!mounted) return;
      setState(() {
        _draft.clear();
        _preview = preview;
      });
    } catch (error) {
      if (!mounted) return;
      if (_denied(error)) {
        _edit(false);
        await _refresh(
            feedback: 'Prüfe deine Berechtigung für diese Installation.');
      } else {
        final code = error is ApiFailure ? error.code : null;
        setState(() => _feedback = switch (code) {
              'LICENSE_PROOF_SUPERSEDED' =>
                'Für diese Lizenz ist bereits eine neuere Fassung gespeichert. Wähle die aktuelle Lizenzdatei.',
              'LICENSE_PROOF_REVISION_CONFLICT' =>
                'Zwei Dateien mit derselben Versionsnummer enthalten unterschiedliche Angaben. Wende dich an den Lizenzaussteller.',
              _ => 'Der Core konnte den Nachweis nicht bestätigen. Prüfe die Originaldatei.',
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(LicensePreview preview) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final status = await widget.api.applyLicense(preview.confirmation);
      if (!mounted) return;
      _edit(false);
      setState(() {
        _status = status;
        _feedback = 'Lizenznachweis gespeichert.';
      });
    } catch (_) {
      if (!mounted) return;
      _edit(false);
      await _refresh(
          feedback:
              'Die Bestätigung ist fehlgeschlagen. Prüfe den aktuellen Status und starte bei Bedarf eine neue Prüfung.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _details(BuildContext context, LicenseStatus status) {
    String entitlement(LicenseEntitlement value) => context.tr(switch (value) {
          LicenseEntitlement.unconfirmed => 'Unbestätigt',
          LicenseEntitlement.notGranted => 'Nicht enthalten',
          LicenseEntitlement.notYetActive => 'Noch nicht aktiv',
          LicenseEntitlement.active => 'Aktiv',
          LicenseEntitlement.ended => 'Beendet',
        });

    return KeyValueGrid(children: [
      KeyValue(
          context.tr('Gewerbliche Nutzung'), entitlement(status.commercial),
          mono: false),
      KeyValue(context.tr('Supportberechtigung'), entitlement(status.support),
          mono: false),
      if (status.licensee case final holder?)
        KeyValue(context.tr('Lizenzinhaber'), holder, mono: false),
      if (status.organization case final organization?)
        KeyValue(context.tr('Organisation'), organization, mono: false),
      if (status.licenseId case final id?)
        KeyValue(context.tr('Lizenzkennung'), id),
      if (status.revision case final revision?)
        KeyValue(context.tr('Fassung'), revision.toString(), mono: false),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final status = _status;
    final preview = _preview;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Panel(
        key: const Key('installation-license'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(context.tr('Nutzungsberechtigung & Support'),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Text(context.tr('Gilt für diese OIP-Installation.')),
          if (_busy) const LinearProgressIndicator(),
          if (status != null) ...[
            KeyValue(
                context.tr('Lizenznachweis'),
                context.tr(switch (status.proofState) {
                  LicenseProofState.unconfigured =>
                    'Lizenzprüfung nicht eingerichtet',
                  LicenseProofState.suspended =>
                    'Lizenzprüfung ausgesetzt',
                  LicenseProofState.missing => 'Kein Nachweis gespeichert',
                  LicenseProofState.invalid => 'Nachweis ungültig',
                  LicenseProofState.verified => 'Nachweis geprüft',
                  LicenseProofState.unavailable => 'Nicht verfügbar',
                }),
                mono: false),
            _details(context, status),
            if (status.proofState != LicenseProofState.verified ||
                status.commercial != LicenseEntitlement.active ||
                status.support != LicenseEntitlement.active)
              Text(context.tr(
                  'Offene Fragen klärt die für diese Installation zuständige Person.')),
          ],
          if (_feedback case final feedback?)
            Semantics(liveRegion: true, child: Text(context.tr(feedback))),
          if (_editing && preview == null) ...[
            const SizedBox(height: 12),
            if (canPickLicenseFile || widget.filePicker != null) ...[
              OutlinedButton.icon(
                key: const Key('choose-license-file'),
                onPressed: _busy ? null : _selectFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(context.tr('Lizenzdatei auswählen')),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const Key('license-proof-input'),
              controller: _draft,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.tr('Inhalt der Lizenzdatei einfügen'),
              ),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 12),
            Text(context.tr('Geprüfter Nachweis zur Übernahme'),
                style: Theme.of(context).textTheme.titleSmall),
            _details(context, preview.status),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_editing) ...[
              TextButton(
                onPressed: _busy ? null : () => _edit(false),
                child: Text(context.tr('Abbrechen')),
              ),
              FilledButton(
                key: Key(
                    preview == null ? 'preview-license' : 'confirm-license'),
                onPressed: _busy
                    ? null
                    : (preview == null ? _review : () => _apply(preview)),
                child: Text(context.tr(preview == null
                    ? 'Nachweis prüfen'
                    : 'Nachweis übernehmen')),
              ),
            ] else ...[
              if (status?.canManage == true)
                OutlinedButton(
                  key: const Key('enter-license-proof'),
                  onPressed: _busy ? null : () => _edit(true),
                  child: Text(context.tr('Lizenznachweis hinterlegen')),
                ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: Text(context.tr('Status aktualisieren')),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
