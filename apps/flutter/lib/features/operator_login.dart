import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../services/api.dart';

/// One-use grant from the authenticated local CLI. No persistent browser token.
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
      await widget.controller.login(value);
    } catch (e) {
      if (mounted) {
        setState(() =>
            error = apiErrorMessage(e, 'Lokale Anmeldung fehlgeschlagen.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Lokale Operator-Anmeldung',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    const Text(
                        'Die reale Infrastruktur ist geschützt. Erzeuge über das autorisierte lokale Operator-Profil einen Einmalcode. Er gilt 120 Sekunden und kann genau einmal verwendet werden.'),
                    const SizedBox(height: 12),
                    const SelectableText(
                        'oip-server --browser-login --ipc-socket <privater Socket> --ipc-credential <eigenes autorisiertes Profil>'),
                    const SizedBox(height: 16),
                    TextField(
                        key: const Key('operator-login-code'),
                        controller: code,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 64,
                        decoration:
                            const InputDecoration(labelText: 'Einmalcode'),
                        onSubmitted: (_) {
                          if (!busy) login();
                        }),
                    if (error != null)
                      Text(error!, key: const Key('login-error')),
                    FilledButton(
                        key: const Key('operator-login'),
                        onPressed: busy ? null : login,
                        child: Text(busy
                            ? 'Anmelden …'
                            : 'Operator-Sitzung autorisieren')),
                    const SizedBox(height: 8),
                    const Text(
                        'Keine langfristigen Zugangsdaten im Browser. Die lokale Sitzung endet nach 30 Minuten oder beim Abmelden.'),
                  ],
                ))),
      ));
}
