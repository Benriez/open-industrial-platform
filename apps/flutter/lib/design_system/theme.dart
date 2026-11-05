import 'package:flutter/material.dart';

/// Visual variants share the same layout and semantics. Spectrum is the default.
enum OipThemeVariant { spectrum, graphite, daylight }

/// Shared visual and behavioural tokens for the OIP workstation.
abstract final class OipTokens {
  static const violet = Color(0xffb57aff);
  static const pink = Color(0xffff74ac);
  static const cyan = Color(0xff39d7ce);
  static const blue = Color(0xff64beff);
  static const yellow = Color(0xfff2c24f);
  static const lime = Color(0xffb9f25e);
  static const red = Color(0xffff7189);

  // Legacy aliases retained for small, independent UI extensions.
  static const mint = cyan;
  static const amber = yellow;

  static const appBackground = Color(0xff0b0d14);
  static const navigation = Color(0xff10131d);
  static const panel = Color(0xff171b27);
  static const mainText = Color(0xfff5f6fa);
  static const secondaryText = Color(0xffa5adc0);

  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;

  static const radiusSm = 10.0;
  static const radius = 16.0;
  static const radiusLg = 22.0;

  static const mobile = 600.0;
  static const tablet = 760.0;
  static const desktop = 1080.0;
  static const workstation = 1000.0;
  static const wide = 1600.0;
  static const motion = Duration(milliseconds: 160);

  static bool isSpectrum(BuildContext context) =>
      Theme.of(context).extension<SpectrumStyle>()?.spectrum ?? false;

  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? (isSpectrum(context) ? secondaryText : const Color(0xffa3acb8))
          : const Color(0xff4f5d70);

  static Color subtleSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? (isSpectrum(context)
              ? const Color(0xff11151f)
              : const Color(0xff15181e))
          : const Color(0xfff3f5fa);

  static Color readableAccent(BuildContext context, Color color) {
    if (Theme.of(context).brightness == Brightness.dark) return color;
    if (color == violet) return const Color(0xff7040b5);
    if (color == pink) return const Color(0xffa21b62);
    if (color == cyan) return const Color(0xff08766f);
    if (color == blue) return const Color(0xff245f96);
    if (color == yellow) return const Color(0xff795400);
    if (color == lime) return const Color(0xff4c7000);
    if (color == red) return const Color(0xffb32635);
    return color;
  }

  static Color categoryColor(BuildContext context, String category) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return switch (category) {
        'network' || 'vpn' => const Color(0xffa21b62),
        'industrial' || 'opcua' => const Color(0xff7040b5),
        'iot' || 'sensor' => const Color(0xff08766f),
        'observability' => const Color(0xff795400),
        'agent' => const Color(0xff4c7000),
        _ => const Color(0xff245f96),
      };
    }
    return switch (category) {
      'network' || 'vpn' => pink,
      'industrial' || 'opcua' => violet,
      'iot' || 'sensor' => cyan,
      'observability' => yellow,
      'agent' => lime,
      _ => blue,
    };
  }

  static Color deviceCategoryColor(BuildContext context, String kind) =>
      switch (kind) {
        'Sensor' || 'Industrial' => categoryColor(context, 'industrial'),
        'Gateway' || 'Bridge' || 'Mobile' => categoryColor(context, 'network'),
        'Media' => categoryColor(context, 'observability'),
        _ => categoryColor(context, 'compute'),
      };

  static Color statusColor(BuildContext context, String? status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case 'alarm':
      case 'bad':
      case 'offline':
      case 'unreachable':
      case 'critical':
        return dark ? red : const Color(0xffb32635);
      case 'degraded':
      case 'stale':
      case 'connecting':
      case 'waiting':
      case 'reconnecting':
      case 'unavailable':
      case 'uncertain':
        return dark ? yellow : const Color(0xff7a4500);
      case 'unknown':
      case 'not_applicable':
      case null:
        return muted(context);
      case 'connected':
      case 'active':
      case 'reachable':
      case 'fresh':
      case 'good':
        return dark ? cyan : const Color(0xff08766f);
      case 'info':
      default:
        return dark ? blue : const Color(0xff315f9b);
    }
  }

  static IconData statusIcon(String? status) => switch (status) {
        'alarm' ||
        'bad' ||
        'offline' ||
        'unreachable' ||
        'critical' =>
          Icons.error_outline,
        'degraded' ||
        'stale' ||
        'connecting' ||
        'waiting' ||
        'reconnecting' ||
        'unavailable' ||
        'uncertain' =>
          Icons.warning_amber_outlined,
        'connected' ||
        'active' ||
        'reachable' ||
        'fresh' ||
        'good' =>
          Icons.check_circle_outline,
        'unknown' || 'not_applicable' || null => Icons.help_outline,
        _ => Icons.info_outline,
      };

  static String statusLabel(String? value) => switch (value) {
        'reachable' => 'Erreichbar',
        'unreachable' => 'Nicht erreichbar',
        'not_applicable' => 'Nicht zutreffend',
        'unavailable' => 'Nicht verfügbar',
        'degraded' => 'Degradiert',
        'offline' => 'Offline',
        'critical' => 'Kritisch',
        'uncertain' => 'Unsicher',
        'connecting' => 'Verbindung wird aufgebaut',
        'waiting' => 'Wartet auf Daten',
        'reconnecting' => 'Verbindung wird aufgebaut',
        'connected' => 'Verbunden',
        'active' => 'Aktiv',
        'fresh' => 'Aktuell',
        'stale' => 'Veraltet',
        'good' => 'Gut',
        'bad' => 'Ungültig',
        'alarm' => 'Alarm',
        'unknown' || null => 'Unbekannt',
        _ => value,
      };

  static ThemeData theme(Brightness brightness, {bool spectrum = true}) {
    final dark = brightness == Brightness.dark;
    final colorful = dark && spectrum;
    final primary = dark
        ? (colorful ? violet : const Color(0xffb8c0cc))
        : const Color(0xff6740a6);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: dark && !colorful ? const Color(0xff16191f) : Colors.white,
      secondary: dark
          ? (colorful ? cyan : const Color(0xffb8c0cc))
          : const Color(0xff245f96),
      onSecondary: dark ? const Color(0xff071c1d) : Colors.white,
      error: dark ? red : const Color(0xffb32635),
      surface:
          dark ? (colorful ? panel : const Color(0xff1b1e24)) : Colors.white,
      onSurface: dark ? mainText : const Color(0xff17202d),
      surfaceContainerHighest: dark
          ? (colorful ? const Color(0xff202536) : const Color(0xff25292f))
          : const Color(0xffe9edf5),
      outline: dark
          ? (colorful ? const Color(0xff30374b) : const Color(0xff373c44))
          : const Color(0xffcbd3df),
      outlineVariant: dark
          ? (colorful ? const Color(0xff242a3a) : const Color(0xff2b3037))
          : const Color(0xffe1e6ee),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? (colorful ? appBackground : const Color(0xff111318))
          : const Color(0xfff2f4f9),
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Arial', 'sans-serif'],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: [SpectrumStyle(spectrum: colorful)],
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            displaySmall: TextStyle(
                fontSize: 32,
                height: 1.16,
                letterSpacing: -1.0,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            headlineLarge: TextStyle(
                fontSize: 30,
                height: 1.18,
                letterSpacing: -.85,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            headlineMedium: TextStyle(
                fontSize: 23,
                height: 1.25,
                letterSpacing: -.45,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            titleLarge: TextStyle(
                fontSize: 18,
                height: 1.3,
                letterSpacing: -.2,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
            titleMedium: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
            titleSmall: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
            bodyLarge:
                TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
            bodyMedium:
                TextStyle(fontSize: 13, height: 1.45, color: scheme.onSurface),
            bodySmall: TextStyle(
                fontSize: 12, height: 1.45, color: mutedFrom(scheme, dark)),
            labelLarge: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
            labelSmall: TextStyle(
                fontSize: 10,
                height: 1.3,
                letterSpacing: 1.25,
                fontWeight: FontWeight.w600,
                color: mutedFrom(scheme, dark)),
          )
          .apply(fontFamily: 'Roboto'),
      dividerColor: scheme.outlineVariant,
      dividerTheme: DividerThemeData(
          color: scheme.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff10141e) : const Color(0xfff8fafc),
        isDense: true,
        hintStyle: TextStyle(color: mutedFrom(scheme, dark), fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: _inputBorder(scheme, radiusSm),
        enabledBorder: _inputBorder(scheme, radiusSm),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: const InputDecorationTheme(),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xff252b3b),
            borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      iconButtonTheme: const IconButtonThemeData(
          style:
              ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(44, 44)))),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            minimumSize: const Size(44, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primary.withOpacity(.18),
        side: BorderSide(color: scheme.outline),
        labelStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minTileHeight: 44,
        iconColor: mutedFrom(scheme, dark),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary, linearMinHeight: 2),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  static Color mutedFrom(ColorScheme scheme, bool dark) =>
      dark ? secondaryText : const Color(0xff4f5d70);

  static OutlineInputBorder _inputBorder(ColorScheme scheme, double radius) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: scheme.outline),
      );
}

class SpectrumStyle extends ThemeExtension<SpectrumStyle> {
  final bool spectrum;
  const SpectrumStyle({required this.spectrum});

  @override
  SpectrumStyle copyWith({bool? spectrum}) =>
      SpectrumStyle(spectrum: spectrum ?? this.spectrum);

  @override
  SpectrumStyle lerp(ThemeExtension<SpectrumStyle>? other, double t) =>
      other is SpectrumStyle && t >= .5 ? other : this;
}
