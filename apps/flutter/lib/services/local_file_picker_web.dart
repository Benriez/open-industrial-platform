import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

const canPickLocalFile = true;

Future<Uint8List?> pickLocalFile(String accept, int maxBytes) async {
  final input = html.FileUploadInputElement()
    ..accept = accept
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
    if (file.size > maxBytes) throw RangeError('Selected file exceeds limit');

    final reader = html.FileReader();
    final done = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(file);
    await done;
    final bytes = reader.result;
    if (reader.error != null || bytes is! Uint8List) {
      throw const FormatException('Selected file could not be read');
    }
    return bytes;
  } finally {
    input.remove();
    await change.cancel();
    await cancel.cancel();
  }
}
