import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../l10n/oip_strings.dart';
import 'support_package_download_stub.dart'
    if (dart.library.html) 'support_package_download_web.dart';

class SupportPackageButton extends StatefulWidget {
  const SupportPackageButton(this.controller, {super.key});

  final OipController controller;

  @override
  State<SupportPackageButton> createState() => _SupportPackageButtonState();
}

class _SupportPackageButtonState extends State<SupportPackageButton> {
  bool busy = false;

  Future<void> _preview() async {
    final controller = widget.controller;
    final scope = controller.contextScopeSignature;
    final label = controller.infrastructure.selectedLabel;
    setState(() => busy = true);
    try {
      final report =
          await controller.api.supportPackage(controller.infrastructure);
      if (!mounted || scope != controller.contextScopeSignature) return;
      final json = const JsonEncoder.withIndent('  ').convert(report);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (scope != controller.contextScopeSignature) {
              return AlertDialog(
                content:
                    Text(context.tr('Der Arbeitskontext hat sich geändert.')),
                actions: [_close(context)],
              );
            }
            return AlertDialog(
              title: Text(context.tr('Supportpaket')),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      const SizedBox(height: 8),
                      Text(context.tr(
                          'Prüfe den Inhalt vor der Weitergabe. OIP sendet das Paket nicht.')),
                      const SizedBox(height: 12),
                      SelectableText(json,
                          key: const Key('support-package-json')),
                    ],
                  ),
                ),
              ),
              actions: [
                _close(context),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: json));
                    if (context.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(context.tr('JSON kopieren')),
                ),
                if (kIsWeb)
                  FilledButton(
                    onPressed: () => downloadSupportPackage(json),
                    child: Text(context.tr('JSON speichern')),
                  ),
              ],
            );
          },
        ),
      );
    } catch (_) {
      if (!mounted || scope != controller.contextScopeSignature) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            'Supportpaket konnte nicht erstellt werden. Prüfe die Anmeldung und deine Berechtigung.')),
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _close(BuildContext context) => TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Schließen')),
      );

  @override
  Widget build(BuildContext context) {
    final infrastructure = widget.controller.infrastructure;
    final selectable = infrastructure.ready &&
        infrastructure.selection.infrastructureId != null;
    return Tooltip(
      message: context.tr(selectable
          ? 'Lokales Supportpaket prüfen'
          : 'Wähle zuerst eine Infrastruktur.'),
      child: TextButton.icon(
        key: const Key('diagnostics-support-package'),
        onPressed: selectable && !busy ? _preview : null,
        icon: const Icon(Icons.description_outlined, size: 18),
        label: Text(context.tr('Supportpaket')),
      ),
    );
  }
}
