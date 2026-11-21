// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void setDocumentLanguage(String languageCode) {
  html.document.documentElement?.lang = languageCode;
}
