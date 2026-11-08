import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design_system/theme.dart';

/// Quiet workstation primitives for the OPC UA explorer.
///
/// Large surfaces stay flat and dark; colour is reserved for foreground
/// semantics (type glyphs, quality, selection). No gradients, blur or
/// perpetual animation. Spectrum, Graphite and Daylight resolve through the
/// existing theme tokens.
abstract final class WorkstationTokens {
  static const rowComfortable = 54.0;
  static const rowDense = 34.0;
  static const radius = 14.0;
  static const radiusSm = 8.0;
  static const glyph = 28.0;

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Primary panel base: between the scaffold and the Material surface.
  static Color panel(BuildContext context) => !_dark(context)
      ? Colors.white
      : OipTokens.isSpectrum(context)
          ? const Color(0xff10131c)
          : const Color(0xff161920);

  /// Recessed well for lists and the value hero.
  static Color well(BuildContext context) => !_dark(context)
      ? const Color(0xfff5f7fb)
      : OipTokens.isSpectrum(context)
          ? const Color(0xff0c0f16)
          : const Color(0xff12151b);

  /// Slightly raised row surface for hover.
  static Color hover(BuildContext context) => !_dark(context)
      ? const Color(0xffeef1f7)
      : OipTokens.isSpectrum(context)
          ? const Color(0xff161a26)
          : const Color(0xff1d2128);

  static Color hairline(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static Color line(BuildContext context) =>
      Theme.of(context).colorScheme.outline;

  /// Tabular Roboto for identifiers, timestamps and values.
  static TextStyle mono(BuildContext context,
          {double? size, Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: size ?? 12,
        height: 1.35,
        letterSpacing: .15,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle eyebrow(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
          fontSize: 9.5,
          letterSpacing: 1.1,
          color: color ?? OipTokens.muted(context));
}

/// Data-type family used for glyphs and grouping. Derived from the OPC UA
/// `data_type` string delivered by the API; nothing is inferred beyond that.
enum NodeTypeFamily { numeric, boolean, text, other }

NodeTypeFamily nodeTypeFamily(String dataType) {
  final value = dataType.toLowerCase();
  if (value.contains('bool')) return NodeTypeFamily.boolean;
  if (value.contains('string') ||
      value.contains('text') ||
      value.contains('localized')) {
    return NodeTypeFamily.text;
  }
  if (value.contains('double') ||
      value.contains('float') ||
      value.contains('int') ||
      value.contains('byte') ||
      value.contains('decimal') ||
      value.contains('number')) {
    return NodeTypeFamily.numeric;
  }
  return NodeTypeFamily.other;
}

String nodeTypeCode(String dataType) => switch (dataType) {
      'Double' => 'f64',
      'Float' => 'f32',
      'Int64' => 'i64',
      'UInt64' => 'u64',
      'Int32' => 'i32',
      'UInt32' => 'u32',
      'Int16' => 'i16',
      'UInt16' => 'u16',
      'Byte' => 'u8',
      'SByte' => 'i8',
      'Boolean' => 'bool',
      'String' => 'str',
      'DateTime' => 'time',
      'ByteString' => 'bytes',
      _ => dataType.length <= 4
          ? dataType.toLowerCase()
          : dataType.substring(0, 3).toLowerCase(),
    };

String nodeTypeFamilyLabel(NodeTypeFamily family) => switch (family) {
      NodeTypeFamily.numeric => 'Numerisch',
      NodeTypeFamily.boolean => 'Boolean',
      NodeTypeFamily.text => 'Text',
      NodeTypeFamily.other => 'Sonstige',
    };

Color nodeTypeColor(BuildContext context, NodeTypeFamily family) =>
    OipTokens.readableAccent(
        context,
        switch (family) {
          NodeTypeFamily.numeric => OipTokens.cyan,
          NodeTypeFamily.boolean => OipTokens.lime,
          NodeTypeFamily.text => OipTokens.blue,
          NodeTypeFamily.other => OipTokens.violet,
        });

/// Flat panel with hairline border and an optional accent top strip.
class WorkstationPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final bool recessed;
  const WorkstationPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OipTokens.s4),
    this.accent,
    this.recessed = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone =
        accent == null ? null : OipTokens.readableAccent(context, accent!);
    final strip = tone == null
        ? null
        : Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                tone.withOpacity(.9),
                tone.withOpacity(.25),
                Colors.transparent
              ], stops: const [
                0,
                .55,
                1
              ]),
            ),
          );
    return Container(
      decoration: BoxDecoration(
        color: recessed
            ? WorkstationTokens.well(context)
            : WorkstationTokens.panel(context),
        border: Border.all(color: WorkstationTokens.line(context)),
        borderRadius: BorderRadius.circular(WorkstationTokens.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final body = Padding(padding: padding, child: child);
        // Bounded parents (workstation columns) let the body fill the panel;
        // unbounded parents (stacked mobile layout) take the natural height.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (strip != null) strip,
            if (constraints.hasBoundedHeight) Expanded(child: body) else body,
          ],
        );
      }),
    );
  }
}

/// Eyebrow label plus optional trailing control; used as a section divider.
///
/// [bottom] allows dense panels to tighten the gap to the following content
/// without changing the default rhythm of the other workstations.
class PanelLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final Color? color;
  final double bottom;
  const PanelLabel(this.text,
      {super.key, this.trailing, this.color, this.bottom = OipTokens.s2});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.eyebrow(context,
                    color: color == null
                        ? null
                        : OipTokens.readableAccent(context, color!))),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class Hairline extends StatelessWidget {
  final double vertical;
  const Hairline({super.key, this.vertical = OipTokens.s3});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Container(height: 1, color: WorkstationTokens.hairline(context)),
      );
}

/// Data-type glyph: rounded square with a short type code.
class TypeGlyph extends StatelessWidget {
  final String dataType;
  final double size;
  final bool active;
  const TypeGlyph(this.dataType,
      {super.key, this.size = WorkstationTokens.glyph, this.active = false});

  @override
  Widget build(BuildContext context) {
    final family = nodeTypeFamily(dataType);
    final tone = nodeTypeColor(context, family);
    final code = nodeTypeCode(dataType);
    final familyLabel = nodeTypeFamilyLabel(family);
    return Semantics(
      label: familyLabel == dataType ? dataType : '$familyLabel $dataType',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withOpacity(active ? .22 : .12),
          borderRadius: BorderRadius.circular(size * .28),
          border: Border.all(color: tone.withOpacity(active ? .7 : .3)),
        ),
        child: Text(code,
            style: WorkstationTokens.mono(context,
                size: code.length > 3 ? size * .3 : size * .36,
                color: tone,
                weight: FontWeight.w700)),
      ),
    );
  }
}

/// Keyboard shortcut hint.
class KbdHint extends StatelessWidget {
  final String text;
  const KbdHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.line(context)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: WorkstationTokens.mono(context,
                size: 10, color: OipTokens.muted(context))),
      );
}

/// Compact square tool button for panel toolbars (keeps a 36 px tap target).
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? accent;
  const ToolButton(
      {super.key,
      required this.icon,
      required this.tooltip,
      this.onPressed,
      this.active = false,
      this.accent});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(context, accent ?? OipTokens.violet);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Material(
        color: active ? tone.withOpacity(.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
              border: Border.all(
                  color: active
                      ? tone.withOpacity(.55)
                      : WorkstationTokens.line(context)),
            ),
            child: Semantics(
              button: true,
              label: tooltip,
              selected: active,
              child: Icon(icon,
                  size: 17,
                  color: onPressed == null
                      ? OipTokens.muted(context).withOpacity(.5)
                      : active
                          ? tone
                          : OipTokens.muted(context)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value pair for inspector sections. Values use tabular figures.
class KeyValue extends StatelessWidget {
  final String label, value;
  final Color? color;
  final bool mono;
  final Widget? trailing;

  /// Tighter vertical rhythm for narrow inspector columns.
  final bool dense;
  const KeyValue(this.label, this.value,
      {super.key,
      this.color,
      this.mono = true,
      this.trailing,
      this.dense = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.eyebrow(context)),
          SizedBox(height: dense ? 2 : 3),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(value,
                  style: mono
                      ? WorkstationTokens.mono(context,
                          size: 12.5, color: color)
                      : Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: color)),
            ),
            if (trailing != null) trailing!,
          ]),
        ]),
      );
}

/// Two-column fact layout when wide enough, single column otherwise.
class KeyValueGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  const KeyValueGrid({super.key, required this.children, this.minWidth = 190});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < minWidth * 2 + OipTokens.s4) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children);
        }
        final width = (box.maxWidth - OipTokens.s4) / 2;
        return Wrap(
          spacing: OipTokens.s4,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      });
}

/// Quiet notice without gradients; used for read-only and honesty messages.
class WorkstationNote extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Color? color;
  const WorkstationNote(this.title, this.message,
      {super.key, this.icon = Icons.info_outline, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(context, color ?? OipTokens.violet);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        border: Border(left: BorderSide(color: tone, width: 2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: OipTokens.s3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: tone, fontSize: 12)),
            const SizedBox(height: 2),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// Minimal sparkline for real, in-session samples. Never draws invented data.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  const Sparkline(this.values,
      {super.key, required this.color, this.height = 44});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklinePainter(
              List.of(values), color, WorkstationTokens.hairline(context)),
        ),
      );
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color, grid;
  _SparklinePainter(this.values, this.color, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - .5),
        Offset(size.width, size.height - .5), gridPaint);
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    const top = 4.0, bottom = 4.0;
    final path = Path();
    final area = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height -
          bottom -
          (values[i] - lo) / span * (size.height - top - bottom);
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(area, Paint()..color = color.withOpacity(.08));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final last = values.last;
    final lastPoint = Offset(
        size.width,
        size.height -
            bottom -
            (last - lo) / span * (size.height - top - bottom));
    canvas.drawCircle(lastPoint, 4, Paint()..color = color.withOpacity(.2));
    canvas.drawCircle(lastPoint, 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      color != old.color ||
      grid != old.grid ||
      values.length != old.values.length ||
      (values.isNotEmpty && values.last != old.values.last) ||
      (values.isNotEmpty && values.first != old.values.first);
}
