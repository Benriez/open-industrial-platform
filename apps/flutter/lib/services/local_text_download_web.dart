// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadLocalText(String filename, String contents, String mediaType) {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([contents], mediaType),
  );
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  });
}
