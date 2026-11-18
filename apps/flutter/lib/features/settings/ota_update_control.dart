import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/theme.dart';

const _otaChannel = MethodChannel('org.openindustrial.oip/ota');

class OipOtaUpdateControl extends StatefulWidget {
  const OipOtaUpdateControl({super.key});

  @override
  State<OipOtaUpdateControl> createState() => _OipOtaUpdateControlState();
}

class _OipOtaUpdateControlState extends State<OipOtaUpdateControl> {
  late final Future<bool> available;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    available = _isAvailable();
  }

  Future<bool> _isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _otaChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => checking = true);
    String message;
    try {
      final status = await _otaChannel.invokeMethod<String>('checkForUpdates');
      message = switch (status) {
        'current' => 'Du verwendest die neueste Version.',
        'installing' =>
          'Das Update wird geladen und nach dem Neustart installiert.',
        'deferred' => 'Das Update wurde zurückgestellt.',
        'busy' => 'Eine Update-Prüfung läuft bereits.',
        _ => 'Die Update-Prüfung ist fehlgeschlagen. Bitte später erneut versuchen.',
      };
    } on PlatformException catch (error) {
      message = error.message ??
          'Die Update-Prüfung ist fehlgeschlagen. Bitte später erneut versuchen.';
    } on MissingPluginException {
      message = 'Der direkte OTA-Updater ist auf diesem Build nicht verfügbar.';
    } finally {
      if (mounted) setState(() => checking = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: available,
        builder: (context, snapshot) {
          if (snapshot.data != true) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('settings-check-for-updates'),
                onPressed: checking ? null : _checkForUpdates,
                icon: checking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt),
                label: Text(checking ? 'Suche nach Updates …' : 'Nach Updates suchen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OipTokens.cyan,
                ),
              ),
            ),
          );
        },
      );
}
