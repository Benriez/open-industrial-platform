import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

const canPickLicenseFile = true;

Future<String?> pickLicenseFile(int maxBytes) async {
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json'
    ..style.display = 'none';
  final selection = Completer<html.File?>();
  final change = input.onChange.listen((_) {
    final files = input.files;
    if (!selection.isCompleted) {
      selection.complete(files?.length == 1 ? files!.single : null);
    }
  });
  final cancel = input.on['cancel'].listen((_) {
    if (!selection.isCompleted) selection.complete(null);
  });
  html.document.body!.append(input);
  try {
    input.click();
    final file = await selection.future;
    if (file == null) return null;
    if (file.size > maxBytes) throw RangeError('Licence file exceeds limit');

    final reader = html.FileReader();
    final done = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(file);
    await done;
    final bytes = reader.result;
    if (reader.error != null || bytes is! Uint8List) {
      throw const FormatException('Licence file could not be read');
    }
    final text = utf8.decode(bytes);
    // Dart's UTF-8 decoder drops an initial BOM, which belongs to the artifact.
    final hasBom = bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    return hasBom ? '\uFEFF$text' : text;
  } finally {
    input.remove();
    await change.cancel();
    await cancel.cancel();
  }
}
