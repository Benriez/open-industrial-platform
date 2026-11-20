/// The static identity of the OIP client application.
///
/// The version and the build number mirror the package manifest
/// (`pubspec.yaml`). They are the same source of truth the
/// macOS build consumes, so they are written together with the release. The
/// [manifestDeclaration] constant keeps the exact manifest line next to the
/// fields it describes, so a drift between the manifest and the rendered
/// identity is visible in one place instead of silently diverging.
///
/// The name, the shell identity footer and the data-disclosure note are stable
/// and do not change per build.
class OipApplicationInfo {
  const OipApplicationInfo({
    required this.name,
    required this.version,
    required this.build,
    required this.footer,
    required this.privacyNote,
    required this.license,
  });

  /// The application display name.
  final String name;

  /// The human-readable version, mirroring the `pubspec.yaml` version.
  final String version;

  /// The monotonically increasing build number, mirroring the manifest build.
  final String build;

  /// The approved shell identity shown in the application footer
  /// (`docs/design/OIP_CANONICAL_UI_BASELINE.md` §3).
  final String footer;

  /// The store-ready data-disclosure note shown in the About section.
  final String privacyNote;

  /// The software license identifier (SPDX) shown in the About section for
  /// store-ready attribution. The full license text ships in the repository
  /// `LICENSE` file; this field names the license the client is released under.
  final String license;

  /// The exact `version:` value of `pubspec.yaml`, kept next to the fields it
  /// describes so a drift between the manifest and the rendered identity is
  /// visible in one place.
  static const _packageVersion = '0.3.41';
  static const _packageBuild = '44';
  static const String manifestDeclaration = '$_packageVersion+$_packageBuild';
}

/// The single source of truth for the client identity, rendered in the
/// Settings workstation's About section.
const OipApplicationInfo kOipApplication = OipApplicationInfo(
  name: 'Open Industrial Platform',
  version: String.fromEnvironment('OIP_APP_VERSION',
      defaultValue: OipApplicationInfo._packageVersion),
  build: String.fromEnvironment('OIP_APP_BUILD',
      defaultValue: OipApplicationInfo._packageBuild),
  footer: 'OIP · SPECTRUM 2027',
  privacyNote:
      'Lokal betrieben. OIP sammelt keine Telemetrie und sendet keine Daten nach '
      'außen; autorisierte Geräte- und Hostdaten bleiben im Besitz des Operators.',
  license: 'Apache-2.0',
);
