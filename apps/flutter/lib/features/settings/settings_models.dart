import 'dart:convert';

import '../../models/contracts.dart';

/// Distinguishes an authorized API read from an explicitly labelled test fixture.
enum SettingsDataOrigin { liveApi, contractFixture }

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

List<dynamic> _list(Object? value, String field) {
  if (value is! List) throw FormatException('$field must be a list');
  return value;
}

String _string(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be text');
  return value;
}

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  return _string(value, field);
}

bool _bool(Object? value, String field) {
  if (value is! bool) throw FormatException('$field must be boolean');
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

int? _nullableInt(Object? value, String field) {
  if (value == null) return null;
  return _int(value, field);
}

class SettingValue {
  final String type;
  final Object value;
  const SettingValue(this.type, this.value);

  factory SettingValue.fromJson(Json json) {
    final type = _string(json['type'], 'setting value type');
    final value = json['value'];
    if ((type == 'text' && value is! String) ||
        (type == 'integer' && value is! int) ||
        (type != 'text' && type != 'integer')) {
      throw const FormatException('Invalid typed setting value');
    }
    return SettingValue(type, value);
  }

  String get display => value is String && (value as String).isEmpty
      ? 'Leerer Text (Core-Default)'
      : '$value';
}

class SettingScope {
  final String kind;
  final String? id;
  const SettingScope(this.kind, this.id);

  factory SettingScope.fromJson(Json json) => SettingScope(
        _string(json['kind'], 'scope kind'),
        _nullableString(json['id'], 'scope id'),
      );

  String get display => id == null ? kind : '$kind / $id';
}

class SettingDefinition {
  final String key;
  final String category;
  final String description;
  final SettingValue defaultValue;
  final String dataType;
  final String validation;
  final List<String> scopes;
  final bool inherited;
  final String readPermission;
  final String writePermission;
  final String sensitivity;
  final String persistence;
  final String applyMode;
  final String changeChannel;

  const SettingDefinition({
    required this.key,
    required this.category,
    required this.description,
    required this.defaultValue,
    required this.dataType,
    required this.validation,
    required this.scopes,
    required this.inherited,
    required this.readPermission,
    required this.writePermission,
    required this.sensitivity,
    required this.persistence,
    required this.applyMode,
    required this.changeChannel,
  });

  factory SettingDefinition.fromJson(Json json) => SettingDefinition(
        key: _string(json['key'], 'definition key'),
        category: _string(json['category'], 'definition category'),
        description: _string(json['description'], 'definition description'),
        defaultValue:
            SettingValue.fromJson(_map(json['default'], 'definition default')),
        dataType: _string(json['data_type'], 'definition data type'),
        validation: _string(json['validation'], 'definition validation'),
        scopes: _list(json['scopes'], 'definition scopes')
            .map((v) => _string(v, 'scope'))
            .toList(growable: false),
        inherited: _bool(json['inherited'], 'definition inherited'),
        readPermission:
            _string(json['read_permission'], 'definition read permission'),
        writePermission:
            _string(json['write_permission'], 'definition write permission'),
        sensitivity: _string(json['sensitivity'], 'definition sensitivity'),
        persistence: _string(json['persistence'], 'definition persistence'),
        applyMode: _string(json['apply_mode'], 'definition apply mode'),
        changeChannel:
            _string(json['change_channel'], 'definition change channel'),
      );
}

class SettingRecord {
  final SettingScope scope;
  final String key;
  final SettingValue value;
  final int revision;
  final int updatedMs;
  final String? actor;
  const SettingRecord({
    required this.scope,
    required this.key,
    required this.value,
    required this.revision,
    required this.updatedMs,
    required this.actor,
  });

  factory SettingRecord.fromJson(Json json) => SettingRecord(
        scope: SettingScope.fromJson(_map(json['scope'], 'record scope')),
        key: _string(json['key'], 'record key'),
        value: SettingValue.fromJson(_map(json['value'], 'record value')),
        revision: _int(json['revision'], 'record revision'),
        updatedMs: _int(json['updated_ms'], 'record update time'),
        actor: _nullableString(json['actor'], 'record actor'),
      );
}

class EffectiveSetting {
  final String key;
  final SettingScope requestedScope;
  final SettingRecord? persisted;
  final SettingValue effective;
  final SettingScope? origin;
  final int effectiveRevision;
  final String applyStatus;

  const EffectiveSetting({
    required this.key,
    required this.requestedScope,
    required this.persisted,
    required this.effective,
    required this.origin,
    required this.effectiveRevision,
    required this.applyStatus,
  });

  factory EffectiveSetting.fromJson(Json json) => EffectiveSetting(
        key: _string(json['key'], 'effective key'),
        requestedScope: SettingScope.fromJson(
            _map(json['requested_scope'], 'requested scope')),
        persisted: json['persisted'] == null
            ? null
            : SettingRecord.fromJson(_map(json['persisted'], 'persisted')),
        effective:
            SettingValue.fromJson(_map(json['effective'], 'effective value')),
        origin: json['origin'] == null
            ? null
            : SettingScope.fromJson(_map(json['origin'], 'origin')),
        effectiveRevision:
            _int(json['effective_revision'], 'effective revision'),
        applyStatus: _string(json['apply_status'], 'apply status'),
      );
}

class SettingsCategoryDefinition {
  final String category;
  final String status;
  final List<String> capabilities;
  const SettingsCategoryDefinition(
      this.category, this.status, this.capabilities);

  factory SettingsCategoryDefinition.fromJson(Json json) =>
      SettingsCategoryDefinition(
        _string(json['category'], 'category'),
        _string(json['status'], 'category status'),
        _list(json['capabilities'], 'category capabilities')
            .map((v) => _string(v, 'capability'))
            .toList(growable: false),
      );
}

class SettingsSnapshot {
  final List<SettingDefinition> definitions;
  final List<SettingsCategoryDefinition> categories;
  final List<EffectiveSetting> settings;
  final int? loadedAtMs;
  final String inheritance;
  final SettingsDataOrigin origin;
  const SettingsSnapshot({
    required this.definitions,
    required this.categories,
    required this.settings,
    required this.loadedAtMs,
    required this.inheritance,
    this.origin = SettingsDataOrigin.liveApi,
  });

  factory SettingsSnapshot.fromJson(Json json,
          {SettingsDataOrigin origin = SettingsDataOrigin.liveApi}) =>
      SettingsSnapshot(
        definitions: _list(json['definitions'], 'definitions')
            .map((v) => SettingDefinition.fromJson(_map(v, 'definition')))
            .toList(growable: false),
        categories: _list(json['categories'], 'categories')
            .map(
                (v) => SettingsCategoryDefinition.fromJson(_map(v, 'category')))
            .toList(growable: false),
        settings: _list(json['settings'], 'settings')
            .map((v) => EffectiveSetting.fromJson(_map(v, 'setting')))
            .toList(growable: false),
        loadedAtMs: _nullableInt(json['loaded_at_ms'], 'loaded time'),
        inheritance: _string(json['inheritance'], 'inheritance'),
        origin: origin,
      );
}

class ManagementFact {
  final String name;
  final String value;
  const ManagementFact(this.name, this.value);
  factory ManagementFact.fromJson(Json json) => ManagementFact(
      _string(json['name'], 'fact name'), _string(json['value'], 'fact value'));
}

class ManagedTool {
  final String name;
  final String description;
  final String capability;
  final List<String> permissions;
  final bool registered;
  final bool availableToPrincipal;
  final bool runtimeAvailable;
  final String availability;
  final List<String> supportedScopes;
  final String classification;
  final String inputSchemaJson;
  final String outputSchemaJson;
  const ManagedTool({
    required this.name,
    required this.description,
    required this.capability,
    required this.permissions,
    required this.registered,
    required this.availableToPrincipal,
    required this.runtimeAvailable,
    required this.availability,
    required this.supportedScopes,
    required this.classification,
    required this.inputSchemaJson,
    required this.outputSchemaJson,
  });

  factory ManagedTool.fromJson(Json json) {
    final input = _string(json['input_schema_json'], 'input schema');
    final output = _string(json['output_schema_json'], 'output schema');
    // Validate at the API boundary. The inspector never renders invalid JSON as
    // a valid schema, and schema visibility never grants tool execution.
    jsonDecode(input);
    jsonDecode(output);
    return ManagedTool(
      name: _string(json['name'], 'tool name'),
      description: _string(json['description'], 'tool description'),
      capability: _string(json['capability'], 'tool capability'),
      permissions: _list(json['permissions'], 'tool permissions')
          .map((v) => _string(v, 'permission'))
          .toList(growable: false),
      registered: _bool(json['registered'], 'registered'),
      availableToPrincipal:
          _bool(json['available_to_principal'], 'principal availability'),
      runtimeAvailable:
          _bool(json['runtime_available'], 'runtime availability'),
      availability: _string(json['availability'], 'tool availability'),
      supportedScopes: _list(json['supported_scopes'], 'supported scopes')
          .map((v) => _string(v, 'supported scope'))
          .toList(growable: false),
      classification: _string(json['classification'], 'classification'),
      inputSchemaJson: input,
      outputSchemaJson: output,
    );
  }

  String prettySchema({required bool output}) {
    final value = jsonDecode(output ? outputSchemaJson : inputSchemaJson);
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

class ClientConfigurationPreview {
  final String? executable;
  final List<String> args;
  final bool usableWithoutReplacement;
  final bool credentialProvisioned;
  final String configurationJson;
  const ClientConfigurationPreview({
    required this.executable,
    required this.args,
    required this.usableWithoutReplacement,
    required this.credentialProvisioned,
    required this.configurationJson,
  });

  factory ClientConfigurationPreview.fromJson(Json json) {
    final configuration = _string(json['configuration_json'], 'configuration');
    final parsed = jsonDecode(configuration);
    final root = _map(parsed, 'configuration root');
    final servers = _map(root['mcpServers'], 'mcpServers');
    final local = _map(servers['oip-local'], 'oip-local');
    _string(local['command'], 'configuration command');
    _list(local['args'], 'configuration args')
        .forEach((v) => _string(v, 'configuration argument'));
    return ClientConfigurationPreview(
      executable: _nullableString(json['executable'], 'executable'),
      args: _list(json['args'], 'args')
          .map((v) => _string(v, 'argument'))
          .toList(growable: false),
      usableWithoutReplacement:
          _bool(json['usable_without_replacement'], 'template usability'),
      credentialProvisioned:
          _bool(json['credential_provisioned'], 'credential provisioning'),
      configurationJson: configuration,
    );
  }

  String get prettyConfiguration {
    final value = const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(configurationJson));
    return value;
  }

  String get cliTemplate =>
      '${executable ?? '<ABSOLUTE_OIP_SERVER_EXECUTABLE>'} ${args.join(' ')}';
}

class ManagementReport {
  final String section;
  final String availability;
  final List<ManagementFact> facts;
  final List<ManagedTool> tools;
  final ClientConfigurationPreview? clientConfiguration;
  final List<String> limitations;
  final SettingsDataOrigin origin;
  const ManagementReport({
    required this.section,
    required this.availability,
    required this.facts,
    required this.tools,
    required this.clientConfiguration,
    required this.limitations,
    this.origin = SettingsDataOrigin.liveApi,
  });

  factory ManagementReport.fromJson(Json json,
          {SettingsDataOrigin origin = SettingsDataOrigin.liveApi}) =>
      ManagementReport(
        section: _string(json['section'], 'management section'),
        availability: _string(json['availability'], 'management availability'),
        facts: _list(json['facts'], 'management facts')
            .map((v) => ManagementFact.fromJson(_map(v, 'fact')))
            .toList(growable: false),
        tools: _list(json['tools'], 'management tools')
            .map((v) => ManagedTool.fromJson(_map(v, 'tool')))
            .toList(growable: false),
        clientConfiguration: json['client_configuration'] == null
            ? null
            : ClientConfigurationPreview.fromJson(
                _map(json['client_configuration'], 'client configuration')),
        limitations: _list(json['limitations'], 'limitations')
            .map((v) => _string(v, 'limitation'))
            .toList(growable: false),
        origin: origin,
      );

  String fact(String name) =>
      facts.where((item) => item.name == name).firstOrNull?.value ?? 'Unknown';
}
