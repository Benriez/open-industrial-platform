import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'messages.dart';

const oipLocales = [Locale('de'), Locale('en')];

class OipStrings {
  const OipStrings(this.locale);

  final Locale locale;
  static const delegate = _OipStringsDelegate();
  static final _placeholder = RegExp(r'\{(\d+)\}');

  static OipStrings of(BuildContext context) =>
      Localizations.of<OipStrings>(context, OipStrings) ??
      const OipStrings(Locale('de'));

  /// Parameters are inserted once, after lookup. Device names, source IDs,
  /// measurements and other values supplied by the Core stay verbatim.
  String message(String source, [List<Object?> arguments = const []]) {
    final catalog =
        locale.languageCode == 'en' ? englishMessages : germanMessages;
    final template = catalog[source] ?? source;
    if (arguments.isEmpty) return template;
    return template.replaceAllMapped(_placeholder, (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? '${arguments[index]}' : match[0]!;
    });
  }
}

class _OipStringsDelegate extends LocalizationsDelegate<OipStrings> {
  const _OipStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      oipLocales.any((item) => item.languageCode == locale.languageCode);

  @override
  Future<OipStrings> load(Locale locale) =>
      SynchronousFuture(OipStrings(locale));

  @override
  bool shouldReload(_OipStringsDelegate old) => false;
}

extension OipLocalizedContext on BuildContext {
  String tr(String source, [List<Object?> arguments = const []]) =>
      OipStrings.of(this).message(source, arguments);
}
