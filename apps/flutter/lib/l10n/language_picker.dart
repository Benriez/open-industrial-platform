import 'package:flutter/material.dart';

import 'oip_strings.dart';

class OipLanguageScope extends InheritedWidget {
  const OipLanguageScope({
    super.key,
    required this.onChanged,
    required super.child,
  });

  final ValueChanged<Locale> onChanged;

  static OipLanguageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OipLanguageScope>();

  @override
  bool updateShouldNotify(OipLanguageScope oldWidget) =>
      oldWidget.onChanged != onChanged;
}

class OipLanguagePicker extends StatelessWidget {
  const OipLanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = OipLanguageScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return DropdownButtonFormField<Locale>(
      key: const Key('oip-language'),
      value: OipStrings.of(context).locale,
      decoration: InputDecoration(
        labelText: context.tr('Sprache'),
        helperText: context
            .tr('Die gewählte Sprache wird auf diesem Gerät gespeichert.'),
      ),
      items: const [
        DropdownMenuItem(value: Locale('de'), child: Text('Deutsch')),
        DropdownMenuItem(value: Locale('en'), child: Text('English')),
      ],
      onChanged: (locale) {
        if (locale != null) scope.onChanged(locale);
      },
    );
  }
}
