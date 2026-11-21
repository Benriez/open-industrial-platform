import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../l10n/language_picker.dart';
import '../l10n/oip_strings.dart';
import '../services/api.dart';
import '../services/touch_id.dart';

/// Initial one-use grant, with optional native macOS Touch ID pairing.
class OperatorLogin extends StatefulWidget {
  final OipController controller;
  const OperatorLogin(this.controller, {super.key});
  @override
  State<OperatorLogin> createState() => _OperatorLoginState();
}

class _OperatorLoginState extends State<OperatorLogin> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  bool hasTouchId = false;
  bool touchIdConfigured = false;
  bool enableTouchIdAfterLogin = false;
  bool _touchIdChoiceMade = false;
  @override
  void initState() {
    super.initState();
    _loadTouchId();
  }

  Future<void> _loadTouchId() async {
    final available = await touchIdAvailable();
    final configured = available && await touchIdCredentialExists();
    if (mounted) {
      setState(() {
        hasTouchId = available;
        touchIdConfigured = configured;
        if (!_touchIdChoiceMade) {
          // Touch ID is the operator's requested way to restore a session
          // after restart. Make the one-time enrollment step visible and
          // selected when this Mac supports it but has no OIP credential yet.
          enableTouchIdAfterLogin = available && !configured;
        }
      });
    }
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    final value = code.text.trim();
    code.clear();
    try {
      await widget.controller
          .login(value, enableTouchId: enableTouchIdAfterLogin && hasTouchId);
    } catch (e) {
      if (mounted) {
        setState(() => error =
            apiErrorMessage(e, context.tr("Lokale Anmeldung fehlgeschlagen.")));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loginWithTouchId() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.loginWithTouchId();
    } catch (e) {
      if (mounted) {
        setState(() => error = apiErrorMessage(
            e, context.tr("Touch-ID-Anmeldung fehlgeschlagen.")));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
              child: Center(
                  child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr("Lokale Operator-Anmeldung"),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    Text(context.tr(
                        "Die reale Infrastruktur ist geschützt. Erzeuge über das autorisierte lokale Operator-Profil einen Einmalcode. Er gilt 120 Sekunden und kann genau einmal verwendet werden.")),
                    const SizedBox(height: 12),
                    SelectableText(context.tr(
                        "oip-server --browser-login --ipc-socket <privater Socket> --ipc-credential <eigenes autorisiertes Profil>")),
                    const SizedBox(height: 16),
                    TextField(
                        key: const Key('operator-login-code'),
                        controller: code,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 64,
                        decoration: InputDecoration(
                            labelText: context.tr("Einmalcode")),
                        onSubmitted: (_) {
                          if (!busy) login();
                        }),
                    if (hasTouchId) ...[
                      CheckboxListTile(
                        key: const Key('enable-touch-id'),
                        contentPadding: EdgeInsets.zero,
                        value: enableTouchIdAfterLogin,
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                  _touchIdChoiceMade = true;
                                  enableTouchIdAfterLogin = value ?? false;
                                }),
                        title: Text(context.tr(
                            "Touch ID für künftige Anmeldungen einrichten")),
                        subtitle: Text(context.tr(
                            "Für die erste Anmeldung brauchst du einen Einmalcode und bestätigst deinen Fingerabdruck. Danach kannst du dich mit Touch ID erneut anmelden.")),
                      ),
                      if (touchIdConfigured)
                        OutlinedButton.icon(
                          key: const Key('operator-login-touch-id'),
                          onPressed: busy ? null : loginWithTouchId,
                          icon: const Icon(Icons.fingerprint),
                          label: Text(context.tr("Mit Touch ID anmelden")),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (error != null)
                      Text(error!, key: const Key('login-error')),
                    FilledButton(
                        key: const Key('operator-login'),
                        onPressed: busy ? null : login,
                        child: Text(busy
                            ? context.tr("Anmelden …")
                            : context.tr("Operator-Sitzung autorisieren"))),
                    const SizedBox(height: 8),
                    Text(context.tr(
                        "Die lokale Sitzung hat kein Zeitlimit. Sie endet beim Abmelden oder mit einem Neustart der Instanz. Mit eingerichteter Touch ID kannst du danach eine neue Sitzung öffnen. Sonst brauchst du einen neuen Einmalcode.")),
                    const SizedBox(height: 16),
                    const OipLanguagePicker(),
                  ],
                ))),
      ))));
}
