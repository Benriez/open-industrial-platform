import 'contracts.dart';

enum LicenseProofState {
  unconfigured,
  suspended,
  missing,
  invalid,
  verified,
  unavailable,
}

enum LicenseEntitlement {
  unconfirmed('unconfirmed'),
  notGranted('not_granted'),
  notYetActive('not_yet_active'),
  active('active'),
  ended('ended');

  const LicenseEntitlement(this.wireName);
  final String wireName;

  static LicenseEntitlement fromWire(Object? value) =>
      values.singleWhere((status) => status.wireName == value);
}

class LicenseStatus {
  final LicenseProofState proofState;
  final LicenseEntitlement commercial, support;
  final String? licenseId, licensee, organization;
  final int? revision;
  final bool canManage;

  const LicenseStatus({
    required this.proofState,
    required this.commercial,
    required this.support,
    required this.canManage,
    this.licenseId,
    this.revision,
    this.licensee,
    this.organization,
  });

  factory LicenseStatus.fromJson(Json json) => LicenseStatus(
        proofState:
            LicenseProofState.values.byName(json['proof_state'] as String),
        commercial: LicenseEntitlement.fromWire(json['commercial']),
        support: LicenseEntitlement.fromWire(json['support']),
        licenseId: json['license_id'] as String?,
        revision: json['revision'] as int?,
        licensee: json['licensee'] as String?,
        organization: json['organization'] as String?,
        canManage: json['can_manage'] as bool,
      );
}

class LicenseProof {
  final String artifact;

  const LicenseProof(this.artifact);

  Json toJson() => {'artifact': artifact};
}

class LicensePreview {
  final LicenseStatus status;
  final String confirmation;

  const LicensePreview(this.status, this.confirmation);

  factory LicensePreview.fromJson(Json json) {
    final status = LicenseStatus.fromJson(json['status'] as Json);
    final confirmation = json['confirmation'] as String;
    if (status.proofState != LicenseProofState.verified ||
        confirmation.isEmpty) {
      throw const FormatException('Missing verified preview');
    }
    return LicensePreview(status, confirmation);
  }
}
