import 'dart:math' as math;

import '../models/contracts.dart';

/// Presentation-only value modes. The original API value is never replaced.
enum OpcValueFormat { original, localized, scientific, engineering }

String opcValueFormatLabel(OpcValueFormat mode) => switch (mode) {
      OpcValueFormat.original => 'Original',
      OpcValueFormat.localized => 'Lokalisiert',
      OpcValueFormat.scientific => 'Wissenschaft',
      OpcValueFormat.engineering => 'Technisch',
    };

/// Exact source representation exposed by the parsed JSON value.
///
/// JSON numbers are already decoded by Dart. `toString()` is the shortest
/// round-trip representation for doubles and remains exact for integers; it is
/// preferable to a lossy `toDouble()` conversion for UInt64/Int64 values.
String originalObservationValue(Observation? observation) {
  if (observation == null) return 'Unbekannt';
  if (!observation.valueValid) return 'Ungültiger Wert';
  final value = observation.value;
  if (value == null) return 'Unbekannt';
  return value.toString();
}

/// Formats values without parsing strings as numbers and without SI prefixes.
/// Numeric notation changes operate on decimal digits, not binary arithmetic.
String formatObservationValue(
  Observation? observation,
  OpcValueFormat mode,
) {
  final original = originalObservationValue(observation);
  final value = observation?.value;
  if (observation == null ||
      !observation.valueValid ||
      value == null ||
      value is! num ||
      mode == OpcValueFormat.original) {
    return original;
  }
  if (!value.isFinite) return original;
  final decimal = _DecimalRepresentation.parse(original);
  if (decimal == null) return original;
  return switch (mode) {
    OpcValueFormat.original => original,
    OpcValueFormat.localized => decimal.localized(),
    OpcValueFormat.scientific => decimal.scientific(),
    OpcValueFormat.engineering => decimal.engineering(),
  };
}

String observationValueWithUnit(
  Observation? observation,
  OpcValueFormat mode,
) {
  final value = formatObservationValue(observation, mode);
  final symbol = observation?.symbol ?? '';
  return '$value $symbol'.trim();
}

/// Facts derivable exclusively from samples received in this UI session.
/// No statement about server-side retention, historian coverage or data loss.
class SessionAnalysis {
  final int sampleCount, numericSampleCount, qualityChanges;
  final num? minimum, maximum;
  final int? firstSourceMs, lastSourceMs, lastReceivedMs, largestSampleGapMs;

  const SessionAnalysis({
    required this.sampleCount,
    required this.numericSampleCount,
    required this.qualityChanges,
    required this.minimum,
    required this.maximum,
    required this.firstSourceMs,
    required this.lastSourceMs,
    required this.lastReceivedMs,
    required this.largestSampleGapMs,
  });

  int? get sourceRangeMs => firstSourceMs == null || lastSourceMs == null
      ? null
      : lastSourceMs! - firstSourceMs!;

  static SessionAnalysis fromSamples(List<Observation> samples) {
    final ordered = samples.where((sample) => sample.sourceMs != null).toList()
      ..sort((a, b) => a.sourceMs!.compareTo(b.sourceMs!));
    final numbers = ordered
        .where((sample) => sample.quality == 'good')
        .map((sample) => sample.value)
        .whereType<num>()
        .where((value) => value.isFinite)
        .toList();
    var qualityChanges = 0;
    for (var index = 1; index < ordered.length; index++) {
      if (ordered[index - 1].quality != ordered[index].quality) {
        qualityChanges++;
      }
    }
    var largestGap = 0;
    for (var index = 1; index < ordered.length; index++) {
      largestGap = math.max(
          largestGap, ordered[index].sourceMs! - ordered[index - 1].sourceMs!);
    }
    return SessionAnalysis(
      sampleCount: ordered.length,
      numericSampleCount: numbers.length,
      qualityChanges: qualityChanges,
      minimum: numbers.isEmpty ? null : numbers.reduce(math.min),
      maximum: numbers.isEmpty ? null : numbers.reduce(math.max),
      firstSourceMs: ordered.firstOrNull?.sourceMs,
      lastSourceMs: ordered.lastOrNull?.sourceMs,
      lastReceivedMs: ordered.lastOrNull?.receivedMs,
      largestSampleGapMs: ordered.length < 2 ? null : largestGap,
    );
  }
}

class _DecimalRepresentation {
  final bool negative;
  final String digits;
  final int scientificExponent;

  const _DecimalRepresentation(
      this.negative, this.digits, this.scientificExponent);

  static _DecimalRepresentation? parse(String source) {
    var value = source;
    var negative = false;
    if (value.startsWith('-') || value.startsWith('+')) {
      negative = value.startsWith('-');
      value = value.substring(1);
    }
    final exponentParts = value.split(RegExp('[eE]'));
    if (exponentParts.length > 2) return null;
    final explicitExponent =
        exponentParts.length == 2 ? int.tryParse(exponentParts[1]) : 0;
    if (explicitExponent == null) return null;
    final mantissa = exponentParts[0].split('.');
    if (mantissa.length > 2 ||
        mantissa.any((part) => !RegExp(r'^\d*$').hasMatch(part))) {
      return null;
    }
    final rawDigits = mantissa.join();
    if (rawDigits.isEmpty) return null;
    final first = rawDigits.indexOf(RegExp(r'[1-9]'));
    if (first < 0) {
      return const _DecimalRepresentation(false, '0', 0);
    }
    final decimalPosition = mantissa[0].length + explicitExponent;
    return _DecimalRepresentation(
        negative, rawDigits.substring(first), decimalPosition - first - 1);
  }

  String get sign => negative ? '-' : '';

  String localized() {
    if (digits == '0') return '0';
    final integerDigits = scientificExponent + 1;
    var plain = '';
    if (integerDigits <= 0) {
      plain = '0.${'0' * -integerDigits}$digits';
    } else if (integerDigits >= digits.length) {
      plain = '$digits${'0' * (integerDigits - digits.length)}';
    } else {
      plain = '${digits.substring(0, integerDigits)}.'
          '${digits.substring(integerDigits)}';
    }
    final parts = plain.split('.');
    final grouped = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.');
    return '$sign$grouped${parts.length == 2 ? ',${parts[1]}' : ''}';
  }

  String scientific() {
    if (digits == '0') return '0e0';
    final fraction = digits.length == 1 ? '' : ',${digits.substring(1)}';
    return '$sign${digits[0]}${fraction}e$scientificExponent';
  }

  String engineering() {
    if (digits == '0') return '0e0';
    final exponent = (scientificExponent / 3).floor() * 3;
    final shift = scientificExponent - exponent;
    final integerLength = shift + 1;
    final padded = integerLength >= digits.length
        ? '$digits${'0' * (integerLength - digits.length)}'
        : digits;
    final integer = padded.substring(0, integerLength);
    final fraction = integerLength >= digits.length
        ? ''
        : ',${digits.substring(integerLength)}';
    return '$sign$integer${fraction}e$exponent';
  }
}
