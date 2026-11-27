import 'dart:convert';

import '../../services/local_file_picker_web.dart';

const canPickLicenseFile = canPickLocalFile;

Future<String?> pickLicenseFile(int maxBytes) async {
  final bytes = await pickLocalFile('.json,application/json', maxBytes);
  if (bytes == null) return null;
  final text = utf8.decode(bytes);
  // Dart's UTF-8 decoder drops an initial BOM, which belongs to the artifact.
  final hasBom = bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\uFEFF$text' : text;
}
