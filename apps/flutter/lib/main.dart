import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app/app.dart';
import 'app/controller.dart';
import 'services/api.dart';

SemanticsHandle? accessibility;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  accessibility = SemanticsBinding.instance.ensureSemantics();
  const configured = String.fromEnvironment('OIP_API_URL');
  final base = configured.isNotEmpty
      ? Uri.parse(configured)
      : kIsWeb
          ? Uri.base
          : Uri.parse('http://127.0.0.1:8080');
  runApp(OipApp(
    controller: OipController(RestApi(base)),
    ownsController: true,
  ));
}
