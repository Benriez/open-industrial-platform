import 'contracts.dart';

/// Integration seam for the global OIP-009 context. No second global selector.
class OnboardingScope {
  final String? organization, infrastructure, site;
  const OnboardingScope({this.organization, this.infrastructure, this.site});
}

class BrowserSession {
  final bool authenticated;
  final String mode;
  final String? principalId;
  BrowserSession.fromJson(Json j)
      : authenticated = j['authenticated'] as bool,
        mode = j['mode'] as String,
        principalId = j['principal_id'] as String?;
}

class HierarchyItem {
  final String id, name;
  HierarchyItem.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String;
}

class SshProfile {
  final String id, label;
  final List<String> aliases;
  SshProfile.fromJson(Json j)
      : id = j['id'] as String,
        label = j['label'] as String,
        aliases = List<String>.from(j['aliases'] as List);
}

class ConnectionPlan {
  final String id, deviceId, stage;
  final String? fingerprint;
  final bool trusted;
  final Json? identity, error;
  ConnectionPlan.fromJson(Json j)
      : id = j['plan_id'] as String,
        deviceId = j['device_id'] as String,
        stage = j['stage'] as String,
        fingerprint = j['host_key_fingerprint'] as String?,
        trusted = j['host_key_trusted'] as bool,
        identity = j['identity'] as Json?,
        error = j['error'] as Json?;
}

class DeviceConnection {
  final String deviceId, status, fingerprint;
  final Json endpoint, identity;
  final Json? error;
  final bool enabled;
  final int revision, pollSeconds;
  final int? lastAttempt, lastSuccess;
  final List<Observation> observations;
  DeviceConnection.fromJson(Json j)
      : deviceId = j['device_id'] as String,
        status = j['status'] as String,
        fingerprint = j['fingerprint'] as String,
        endpoint = j['endpoint'] as Json,
        identity = j['verified_identity'] as Json,
        error = j['error'] as Json?,
        enabled = j['monitoring_enabled'] as bool,
        revision = j['revision'] as int,
        pollSeconds = j['poll_seconds'] as int,
        lastAttempt = j['last_attempt_ms'] as int?,
        lastSuccess = j['last_success_ms'] as int?,
        observations = (j['observations'] as List)
            .map((v) => Observation.fromJson(v as Json))
            .toList();
}

class ConnectionResult {
  final List<SshProfile> profiles;
  final ConnectionPlan? plan;
  final DeviceConnection? connection;
  final Json? lastAttempt;
  ConnectionResult.fromJson(Json j)
      : profiles = (j['profiles'] as List)
            .map((v) => SshProfile.fromJson(v as Json))
            .toList(),
        plan = j['plan'] == null
            ? null
            : ConnectionPlan.fromJson(j['plan'] as Json),
        connection = j['connection'] == null
            ? null
            : DeviceConnection.fromJson(j['connection'] as Json),
        lastAttempt = j['last_attempt'] as Json?;
}
