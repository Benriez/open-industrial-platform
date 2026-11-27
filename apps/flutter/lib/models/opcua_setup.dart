import 'contracts.dart';

enum OpcuaPointKind {
  float('float'),
  signedInteger('signed_integer'),
  unsignedInteger('unsigned_integer'),
  boolean('boolean'),
  text('text');

  const OpcuaPointKind(this.wire);
  final String wire;
}

class OpcuaSetupPoint {
  const OpcuaSetupPoint(this.metric, this.nodeId, this.kind);
  final String metric, nodeId;
  final OpcuaPointKind kind;

  Json toJson() =>
      {'metric': metric, 'node_id': nodeId, 'value_kind': kind.wire};
}

class OpcuaSourceConfiguration {
  const OpcuaSourceConfiguration(this.endpoint, this.serverUri,
      this.namespaceUri, this.pollSeconds, this.points);

  factory OpcuaSourceConfiguration.fromJson(Json json) =>
      OpcuaSourceConfiguration(
        json['endpoint'] as String,
        json['server_application_uri'] as String,
        json['namespace_uri'] as String,
        json['poll_seconds'] as int,
        (json['points'] as List).cast<Json>().map((point) {
          final kind = OpcuaPointKind.values
              .firstWhere((kind) => kind.wire == point['value_kind']);
          return OpcuaSetupPoint(
              point['metric'] as String, point['node_id'] as String, kind);
        }).toList(growable: false),
      );

  final String endpoint, serverUri, namespaceUri;
  final int pollSeconds;
  final List<OpcuaSetupPoint> points;

  Json toJson() => {
        'endpoint': endpoint,
        'server_application_uri': serverUri,
        'namespace_uri': namespaceUri,
        'poll_seconds': pollSeconds,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

sealed class OpcuaSetupResult {
  const OpcuaSetupResult();
  factory OpcuaSetupResult.fromJson(Json json) => switch (json['state']) {
        'unconfigured' => const OpcuaUnconfigured(),
        'preview' => OpcuaCertificatePreview(
            configuration: OpcuaSourceConfiguration.fromJson(
                json['configuration'] as Json),
            certificate: json['certificate'] as Json,
            previousSha256: json['previous_sha256'] as String?,
            confirmation: json['confirmation'] as String,
          ),
        'configured' => OpcuaConfigured(
            source: json['source'] as String,
            configuration: OpcuaSourceConfiguration.fromJson(
                json['configuration'] as Json),
            serverSha256: json['server_sha256'] as String,
            clientCertificate: json['client_certificate_pem'] as String,
            enabled: json['collector_enabled'] as bool,
          ),
        _ => throw const FormatException('Unknown OPC UA setup state'),
      };
}

class OpcuaUnconfigured extends OpcuaSetupResult {
  const OpcuaUnconfigured();
}

class OpcuaCertificatePreview extends OpcuaSetupResult {
  OpcuaCertificatePreview({
    required this.configuration,
    required Json certificate,
    this.previousSha256,
    required this.confirmation,
  })  : fingerprint = certificate['sha256'] as String,
        subject = certificate['subject'] as String,
        validUntil = certificate['valid_until'] as String;
  final OpcuaSourceConfiguration configuration;
  final String fingerprint, subject, validUntil, confirmation;
  final String? previousSha256;
}

class OpcuaConfigured extends OpcuaSetupResult {
  const OpcuaConfigured({
    required this.source,
    required this.configuration,
    required this.serverSha256,
    required this.clientCertificate,
    required this.enabled,
  });
  final String source, serverSha256, clientCertificate;
  final OpcuaSourceConfiguration configuration;
  final bool enabled;
}
