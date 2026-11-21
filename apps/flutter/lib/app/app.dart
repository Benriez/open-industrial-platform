import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design_system/theme.dart';
import '../features/devices.dart';
import '../features/overview.dart';
import '../features/network.dart';
import '../features/opcua.dart';
import '../features/diagnostics.dart';
import '../features/operator_login.dart';
import '../features/settings.dart';
import '../features/version_changelog.dart';
import '../l10n/document_language.dart';
import '../l10n/language_picker.dart';
import '../l10n/oip_strings.dart';
import '../models/app_metadata.dart';
import '../widgets/components.dart';
import '../widgets/adaptive_workspace.dart';
import '../widgets/infrastructure_selector.dart';
import 'controller.dart';

class _BrandMark extends AssetImage {
  const _BrandMark() : super('assets/branding/oip-logo.png');

  @override
  ImageStreamCompleter loadImage(
      AssetBundleImageKey key, ImageDecoderCallback decode) {
    if (!kIsWeb) return super.loadImage(key, decode);
    // A target width selects CanvasKit's PNG codec. Flutter 3.22's browser
    // ImageDecoder path can leave WebCodecs video frames open for a static logo.
    return super.loadImage(
      key,
      (buffer, {getTargetSize}) =>
          ui.instantiateImageCodecFromBuffer(buffer, targetWidth: 128),
    );
  }
}

class OipApp extends StatefulWidget {
  final OipController controller;
  final bool autoStart;
  final bool ownsController;
  const OipApp({
    super.key,
    required this.controller,
    this.autoStart = true,
    this.ownsController = false,
  });

  @override
  State<OipApp> createState() => _OipAppState();
}

class _OipAppState extends State<OipApp> {
  static const _languageKey = 'oip-language';
  Locale _locale = oipLocales.first;
  bool _languageChosen = false;
  OipThemeVariant themeVariant = OipThemeVariant.spectrum;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLanguage());
    if (widget.autoStart) unawaited(widget.controller.start());
  }

  Future<void> _restoreLanguage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_languageKey);
      if (!mounted || _languageChosen) return;
      final selected = oipLocales
          .where((locale) => locale.languageCode == saved)
          .firstOrNull;
      if (selected != null && selected != _locale) {
        setState(() => _locale = selected);
        setDocumentLanguage(selected.languageCode);
      }
    } on PlatformException catch (error) {
      debugPrint('OIP language preference unavailable: ${error.code}');
    } on MissingPluginException {
      // The language can still be changed for the current app instance.
    }
  }

  Future<void> _setLanguage(Locale locale) async {
    setState(() {
      _languageChosen = true;
      _locale = locale;
    });
    setDocumentLanguage(locale.languageCode);
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_locale != locale) return;
      await preferences.setString(_languageKey, locale.languageCode);
    } on PlatformException catch (error) {
      debugPrint('OIP could not save language preference: ${error.code}');
    } on MissingPluginException {
      // The selected language remains active until the app closes.
    }
  }

  @override
  void dispose() {
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  void cycleTheme() => setState(() {
        themeVariant = switch (themeVariant) {
          OipThemeVariant.spectrum => OipThemeVariant.daylight,
          OipThemeVariant.daylight => OipThemeVariant.graphite,
          OipThemeVariant.graphite => OipThemeVariant.spectrum,
        };
      });

  void setTheme(OipThemeVariant value) => setState(() => themeVariant = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Open Industrial Platform',
        debugShowCheckedModeBanner: false,
        locale: _locale,
        supportedLocales: oipLocales,
        localizationsDelegates: const [
          OipStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: OipTokens.theme(Brightness.light),
        darkTheme: OipTokens.theme(
          Brightness.dark,
          spectrum: themeVariant != OipThemeVariant.graphite,
        ),
        themeMode: themeVariant == OipThemeVariant.daylight
            ? ThemeMode.light
            : ThemeMode.dark,
        home: OipLanguageScope(
          onChanged: _setLanguage,
          child: DashboardShell(
            widget.controller,
            dark: themeVariant != OipThemeVariant.daylight,
            themeVariant: themeVariant,
            toggleTheme: cycleTheme,
            setTheme: setTheme,
          ),
        ),
      );
}

const pageTitles = [
  'Übersicht',
  'Geräte & Dienste',
  'Netzwerk & VPN',
  'OPC-UA-Browser',
  'Diagnose & Ereignisse',
  'Einstellungen'
];
const pageIcons = [
  Icons.space_dashboard_outlined,
  Icons.dns_outlined,
  Icons.hub_outlined,
  Icons.account_tree_outlined,
  Icons.radar,
  Icons.settings_outlined
];

Color pageAccent(BuildContext context, int index) {
  final color = switch (index) {
    0 => OipTokens.cyan,
    1 => OipTokens.blue,
    2 => OipTokens.pink,
    3 => OipTokens.violet,
    4 => OipTokens.yellow,
    _ => OipTokens.lime,
  };
  return OipTokens.readableAccent(context, color);
}

Widget spectrumTitle(BuildContext context, String value) {
  final style = Theme.of(context).textTheme.titleLarge;
  if (!OipTokens.isSpectrum(context)) return Text(value, style: style);
  return ShaderMask(
    shaderCallback: (bounds) => const LinearGradient(
      colors: [OipTokens.violet, OipTokens.blue, OipTokens.cyan],
    ).createShader(bounds),
    child: Text(value, style: style?.copyWith(color: Colors.white)),
  );
}

class DashboardShell extends StatefulWidget {
  final OipController controller;
  final VoidCallback toggleTheme;
  final ValueChanged<OipThemeVariant> setTheme;
  final bool dark;
  final OipThemeVariant themeVariant;
  const DashboardShell(
    this.controller, {
    super.key,
    required this.toggleTheme,
    required this.setTheme,
    this.dark = true,
    this.themeVariant = OipThemeVariant.spectrum,
  });

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int page = 0;
  final scroll = ScrollController();
  final devicesSession = DevicesWorkspaceSession();
  final settingsSession = SettingsWorkspaceSession();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void navigate(int index) {
    if (page != index) setState(() => page = index);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= OipTokens.desktop;
    final narrow = width < OipTokens.tablet;
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              width: 284,
              child: SafeArea(child: _sidebar(context, true)),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 224, child: _sidebar(context, false)),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    controller: widget.controller,
                    page: page,
                    wide: wide,
                    narrow: narrow,
                    dark: widget.dark,
                    themeVariant: widget.themeVariant,
                    toggleTheme: widget.toggleTheme,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(
                        narrow ? OipTokens.s4 : OipTokens.s7,
                        narrow ? OipTokens.s5 : OipTokens.s7,
                        narrow ? OipTokens.s4 : OipTokens.s7,
                        OipTokens.s4,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1520),
                          child: ListenableBuilder(
                            listenable: widget.controller,
                            builder: (context, _) => _PageContent(
                              controller: widget.controller,
                              page: page,
                              navigate: navigate,
                              devicesSession: devicesSession,
                              settingsSession: settingsSession,
                              themeVariant: widget.themeVariant,
                              setTheme: widget.setTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, bool drawer) {
    final scheme = Theme.of(context).colorScheme;
    Widget navigationItem(int index) {
      final accent = pageAccent(context, index);
      void select() {
        if (drawer) Navigator.pop(context);
        navigate(index);
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: OipTokens.s1),
        child: Material(
          color: page == index ? accent.withOpacity(.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(OipTokens.radiusSm),
          child: Semantics(
            button: true,
            label:
                context.tr("Navigation {0}", [context.tr(pageTitles[index])]),
            onTap: select,
            child: ExcludeSemantics(
              child: ListTile(
                key: Key('nav-$index'),
                dense: true,
                selected: page == index,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(OipTokens.radiusSm)),
                leading: Icon(
                  pageIcons[index],
                  size: 20,
                  color: page == index ? accent : OipTokens.muted(context),
                ),
                title: Text(
                  context.tr(pageTitles[index]),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        page == index ? FontWeight.w600 : FontWeight.w400,
                    color: page == index ? accent : OipTokens.muted(context),
                  ),
                ),
                onTap: select,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            OipTokens.isSpectrum(context)
                ? OipTokens.navigation
                : scheme.surface,
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
        border: Border(right: BorderSide(color: scheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 16, 28),
            child: Row(
              children: [
                GradientBorder(
                  colors: const [OipTokens.violet, OipTokens.cyan],
                  radius: OipTokens.radiusSm,
                  child: Container(
                    width: 40,
                    height: 40,
                    color: OipTokens.navigation,
                    child: const Image(
                      image: _BrandMark(),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(width: OipTokens.s3),
                Expanded(
                  child: Text(
                    context.tr("OPEN INDUSTRIAL\nPLATFORM"),
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6),
                  ),
                ),
              ],
            ),
          ),
          _navGroupLabel('ARBEITSBEREICH'),
          navigationItem(0),
          navigationItem(1),
          navigationItem(2),
          const SizedBox(height: OipTokens.s5),
          _navGroupLabel('DATEN & ANALYSE'),
          navigationItem(3),
          navigationItem(4),
          const SizedBox(height: OipTokens.s5),
          _navGroupLabel('SYSTEM'),
          navigationItem(5),
          const Spacer(),
          Divider(height: 1, color: scheme.outline),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(24, OipTokens.s3, 16, OipTokens.s4),
            child: Semantics(
              button: true,
              label: context.tr(
                  "Versionshinweise öffnen. Version {0}, Build {1}",
                  [kOipApplication.version, kOipApplication.build]),
              child: InkWell(
                key: const Key('sidebar-app-version'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => showVersionChangelog(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr("VERSION {0} · BUILD {1}",
                              [kOipApplication.version, kOipApplication.build]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: OipTokens.muted(context),
                                    letterSpacing: .35,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.open_in_new,
                          size: 13, color: OipTokens.muted(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navGroupLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 12, 10),
        child: Text(context.tr(label),
            style: Theme.of(context).textTheme.labelSmall),
      );
}

class _TopBar extends StatelessWidget {
  final OipController controller;
  final int page;
  final bool wide, narrow, dark;
  final OipThemeVariant themeVariant;
  final VoidCallback toggleTheme;
  const _TopBar({
    required this.controller,
    required this.page,
    required this.wide,
    required this.narrow,
    required this.dark,
    required this.themeVariant,
    required this.toggleTheme,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: narrow ? OipTokens.s3 : OipTokens.s7,
          vertical: OipTokens.s3,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(.35),
          border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final snapshot = controller.snapshot;
            final scenario = snapshot?.system.scenario;
            final knownScenario = scenarios.containsKey(scenario);
            final simulation = snapshot?.system.simulated ?? false;
            final operatorActionsAvailable = controller.managed &&
                !controller.loginRequired &&
                controller.management != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!wide)
                      Builder(
                        builder: (context) => IconButton(
                          key: const Key('open-navigation'),
                          tooltip: context.tr("Navigation öffnen"),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: const Icon(Icons.menu),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr("WORKSPACE / LOCAL LAB"),
                              style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: OipTokens.s1),
                          spectrumTitle(context, context.tr(pageTitles[page])),
                        ],
                      ),
                    ),
                    if (!narrow)
                      Padding(
                        padding: const EdgeInsets.only(right: OipTokens.s2),
                        child: Text(
                          switch (themeVariant) {
                            OipThemeVariant.spectrum => context.tr("SPECTRUM"),
                            OipThemeVariant.graphite => context.tr("GRAPHITE"),
                            OipThemeVariant.daylight => context.tr("DAYLIGHT"),
                          },
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: pageAccent(context, page)),
                        ),
                      ),
                    IconButton(
                      key: const Key('theme-toggle'),
                      tooltip: context.tr("Darstellung wechseln"),
                      onPressed: toggleTheme,
                      icon: Icon(
                          dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: OipTokens.s2),
                Wrap(
                  spacing: OipTokens.s3,
                  runSpacing: OipTokens.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InfrastructureSelector(
                        controller: controller, narrow: narrow),
                    apiConnectionStatus(context, controller),
                    if (snapshot != null && snapshot.system.demoControls)
                      SizedBox(
                        width: narrow ? 220 : 236,
                        child: DropdownButtonFormField<String>(
                          key: const Key('scenario-select'),
                          isExpanded: true,
                          value: knownScenario ? scenario : null,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.tune, size: 17),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          items: scenarios.entries
                              .map((entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value,
                                        style: const TextStyle(fontSize: 12)),
                                  ))
                              .toList(),
                          onChanged: controller.scenarioBusy ||
                                  !snapshot.system.demoControls
                              ? null
                              : (value) {
                                  if (value != null) {
                                    controller.setScenario(value);
                                  }
                                },
                        ),
                      ),
                    if (controller.scenarioBusy)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    if (!narrow)
                      Tooltip(
                        message: simulation
                            ? context.tr(
                                "Simulation only; no real infrastructure changes.")
                            : !operatorActionsAvailable
                                ? context.tr(
                                    "Authorize a managed operator session to open actions permitted for its scope.")
                                : context.tr(
                                    "Inventory registration and updates, SSH onboarding and monitoring configuration are available when permitted by the current scope. Telemetry is collector-owned; OPC-UA writes require server-reported ReadWrite access and an authorized scope."),
                        child: Text(
                          simulation
                              ? context.tr("Simulation · Self-hosted")
                              : !operatorActionsAvailable
                                  ? context
                                      .tr("Sign in to manage · Self-hosted")
                                  : context
                                      .tr("Operator actions · Self-hosted"),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}

class _PageContent extends StatelessWidget {
  final OipController controller;
  final int page;
  final void Function(int) navigate;
  final DevicesWorkspaceSession devicesSession;
  final SettingsWorkspaceSession settingsSession;
  final OipThemeVariant themeVariant;
  final ValueChanged<OipThemeVariant> setTheme;
  const _PageContent({
    required this.controller,
    required this.page,
    required this.navigate,
    required this.devicesSession,
    required this.settingsSession,
    required this.themeVariant,
    required this.setTheme,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    // A retained snapshot lets the workstation stay usable during a short
    // transport interruption. The header already reports API STALE / RECONNECT,
    // so inserting transient notices here would only push the whole workspace
    // down and back up on every retry.
    final transientReconnectWithSnapshot =
        snapshot != null && controller.connection == 'reconnecting';
    final showConnectionError =
        controller.error != null && !transientReconnectWithSnapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showConnectionError)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s4),
            child: InlineNotice(
              context.tr("Verbindung und Datenaktualität"),
              controller.error!,
              icon: Icons.sync_problem_outlined,
              color: OipTokens.statusColor(context, 'degraded'),
            ),
          ),
        if (controller.scenarioError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s4),
            child: InlineNotice(
              context.tr("Szenariowechsel nicht ausgeführt"),
              controller.scenarioError!,
              icon: Icons.tune,
              color: OipTokens.statusColor(context, 'degraded'),
            ),
          ),
        if (showConnectionError && !controller.loginRequired)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: controller.reconnect,
                icon: const Icon(Icons.refresh, size: 17),
                label: Text(context.tr("Jetzt erneut verbinden")),
              ),
            ),
          ),
        if (snapshot != null &&
            controller.stale &&
            !transientReconnectWithSnapshot)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                context.tr("VERALTET / UNBEKANNT · {0}: {1}", [
                  controller.connection != 'live'
                      ? 'UI-Stream; OPC UA zuletzt'
                      : 'OPC UA primär',
                  known(snapshot.system.opcua)
                ]),
                color: OipTokens.statusColor(context, 'degraded'),
                showDot: true,
              ),
            ),
          ),
        if (controller.loginRequired)
          // A missing session is an identity problem. The old demo dashboard
          // never appears as a substitute for an authorized read.
          OperatorLogin(controller)
        else if (snapshot == null && page != 5)
          StateMessage(
            controller.error == null
                ? context.tr("Verbindung zum lokalen OIP-Server")
                : controller.error!.contains('nicht erreichbar')
                    ? context.tr("Server nicht erreichbar")
                    : context.tr("API-Daten konnten nicht geladen werden"),
            context.tr(
                "REST lädt den Anfangszustand. SSE liefert danach Änderungen."),
            icon: Icons.sensors,
            action: controller.error == null
                ? const Padding(
                    padding: EdgeInsets.all(OipTokens.s5),
                    child: CircularProgressIndicator(),
                  )
                : TextButton(
                    onPressed: controller.reconnect,
                    child: Text(context.tr("Erneut versuchen")),
                  ),
          )
        else
          switch (page) {
            0 => OverviewPage(controller, navigate),
            1 => DevicesPage(controller, navigate, session: devicesSession),
            2 => NetworkPage(controller),
            3 => OpcuaPage(controller),
            4 => DiagnosticsPage(controller),
            5 => SettingsPage(
                controller: controller,
                session: settingsSession,
                themeVariant: themeVariant,
                onTheme: setTheme,
              ),
            _ => StateMessage(
                context.tr("Unbekanntes Modul"),
                context.tr(
                    "Die angeforderte Hauptnavigation ist nicht registriert."),
                icon: Icons.error_outline,
              ),
          },
        const SizedBox(height: OipTokens.s7),
        const Divider(),
        const SizedBox(height: OipTokens.s3),
        Wrap(
          spacing: OipTokens.s3,
          runSpacing: OipTokens.s1,
          children: [
            Text(context.tr("OIP · SPECTRUM 2027"),
                style: Theme.of(context).textTheme.labelSmall),
            Text(
              controller.hasAuthorizedContext
                  ? context.tr("Reale Infrastruktur · lokale Operator-Sitzung")
                  : context.tr("Lokale Entwicklung und Simulation"),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              snapshot == null
                  ? context.tr("Security-Blocker werden vom Server geladen")
                  : snapshot.system.blocker == 'none'
                      ? context.tr("Kein Security-Blocker gemeldet")
                      : snapshot.system.blocker == 'unknown'
                          // The scoped snapshot of a tenant carries no
                          // platform fact. The blocker of the platform is
                          // therefore not delivered to this session: the
                          // footer names that instead of showing a
                          // placeholder as an open blocker.
                          ? context.tr(
                              "Security-Blocker: an diese Sitzung nicht geliefert")
                          : context.tr("{0} offen", [snapshot.system.blocker]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (controller.hasAuthorizedContext)
              TextButton(
                key: const Key('operator-logout'),
                onPressed: () => controller.logout(),
                child: Text(context.tr("Operator abmelden")),
              ),
          ],
        ),
      ],
    );
  }
}
