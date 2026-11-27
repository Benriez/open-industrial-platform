// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadSupportPackage(String json) {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([json], 'application/json;charset=utf-8'),
  );
  html.AnchorElement(href: url)
    ..download = 'oip-support.json'
    ..click();
  Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  });
}
