import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('org.openindustrial.oip/touch_id');

bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

Future<bool> touchIdAvailable() async {
  if (!_isMacOS) return false;
  try {
    return await _channel.invokeMethod<bool>('available') ?? false;
  } on PlatformException {
    return false;
  }
}

Future<String?> createTouchIdCredential() async {
  if (!_isMacOS) return null;
  return _channel.invokeMethod<String>('createCredential');
}

Future<String?> readTouchIdCredential() async {
  if (!_isMacOS) return null;
  return _channel.invokeMethod<String>('readCredential');
}

Future<void> deleteTouchIdCredential() async {
  if (_isMacOS) await _channel.invokeMethod<void>('deleteCredential');
}
