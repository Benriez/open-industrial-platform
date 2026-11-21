import '../l10n/oip_strings.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design_system/theme.dart';
import 'device_kind.dart';

/// A dark surface with a subtle category tint. No blur or perpetual animation.
class SpectrumSurface extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool interactive;

  const SpectrumSurface({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(OipTokens.s5),
    this.radius = OipTokens.radius,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = accent;
    final colorful = OipTokens.isSpectrum(context) && tone != null;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colorful
              ? [tone.withOpacity(.145), tone.withOpacity(.055), scheme.surface]
              : [
                  scheme.surface,
                  Color.lerp(scheme.surface,
                      Theme.of(context).scaffoldBackgroundColor, .24)!
                ],
        ),
        border: Border.all(
            color: colorful ? tone.withOpacity(.31) : scheme.outline),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class GradientCard extends SpectrumSurface {
  const GradientCard({
    super.key,
    required super.child,
    super.accent,
    super.padding,
    super.radius,
  });
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Color? accent;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OipTokens.s5),
    this.color,
    this.borderColor,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (accent != null) {
      return SpectrumSurface(accent: accent, padding: padding, child: child);
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color ?? Theme.of(context).colorScheme.surface,
            Color.lerp(color ?? Theme.of(context).colorScheme.surface,
                Theme.of(context).scaffoldBackgroundColor, .16)!,
          ],
        ),
        border: Border.all(
            color: borderColor ?? Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(OipTokens.radius),
      ),
      child: child,
    );
  }
}

class GradientBorder extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final double radius;
  const GradientBorder(
      {super.key,
      required this.child,
      required this.colors,
      this.radius = OipTokens.radius});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: child,
        ),
      );
}

class AccentHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  final Color? accent;
  final IconData? icon;
  const AccentHeader(this.title, this.subtitle,
      {super.key, this.action, this.accent, this.icon});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(
        context, accent ?? Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: OipTokens.s4),
      child: Wrap(
        spacing: OipTokens.s3,
        runSpacing: OipTokens.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (icon != null)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: tone.withOpacity(.13),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: tone),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: tone)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  final Color? accent;
  const SectionTitle(this.title, this.subtitle,
      {super.key, this.action, this.accent});

  @override
  Widget build(BuildContext context) => AccentHeader(title, subtitle,
      action: action,
      accent: accent ?? Theme.of(context).colorScheme.onSurface);
}

class SectionContainer extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  final Widget? action;
  final Color accent;
  final IconData? icon;
  const SectionContainer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.accent,
    this.action,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => GradientCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentHeader(title, subtitle,
                action: action, accent: accent, icon: icon),
            child,
          ],
        ),
      );
}

class ChartContainer extends SectionContainer {
  const ChartContainer({
    super.key,
    required super.title,
    required super.subtitle,
    required super.child,
    required super.accent,
    super.action,
    super.icon = Icons.show_chart,
  });
}

class MetricTile extends StatelessWidget {
  final String label, value, foot;
  final IconData icon;
  final Color? color;
  const MetricTile(this.label, this.value, this.foot, this.icon,
      {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(
        context, color ?? OipTokens.categoryColor(context, 'compute'));
    return GradientCard(
      accent: tone,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OipTokens.radius),
        child: Stack(
          children: [
            Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: tone)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 16, 15),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 116),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(label.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: tone, letterSpacing: .85)),
                      ),
                      const SizedBox(width: 8),
                      Icon(icon, size: 18, color: tone),
                    ]),
                    const SizedBox(height: OipTokens.s3),
                    Text(value,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(color: tone, fontSize: 29)),
                    const SizedBox(height: OipTokens.s2),
                    Text(foot,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricCard extends MetricTile {
  const MetricCard(super.label, super.value, super.foot, super.icon,
      {super.key, super.color});
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color? color;
  final bool showDot;
  final IconData? icon;
  const StatusPill(this.text,
      {super.key, this.color, this.showDot = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(
        context, color ?? Theme.of(context).colorScheme.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withOpacity(.12),
        border: Border.all(color: tone.withOpacity(.35)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (showDot)
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle))
        else if (icon != null)
          Icon(icon, size: 12, color: tone),
        if (showDot || icon != null) const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .25,
                  color: tone)),
        ),
      ]),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final String? status;
  final double size;
  final bool labelled;
  const StatusIndicator(this.status,
      {super.key, this.size = 8, this.labelled = false});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.statusColor(context, status);
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone,
        shape: BoxShape.circle,
        border:
            Border.all(color: Theme.of(context).colorScheme.surface, width: 1),
      ),
    );
    return Semantics(
      label: context.tr("Status: {0}", [OipTokens.statusLabel(status)]),
      child: labelled
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              dot,
              const SizedBox(width: 6),
              Flexible(
                  child: Text(OipTokens.statusLabel(status),
                      overflow: TextOverflow.ellipsis)),
            ])
          : dot,
    );
  }
}

class StatusDot extends StatusIndicator {
  const StatusDot(super.status, {super.key, super.size});
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  final double spacing;
  const ResponsiveGrid(
      {super.key,
      required this.children,
      this.minWidth = 240,
      this.maxColumns = 4,
      this.spacing = OipTokens.s3});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = ((box.maxWidth + spacing) / (minWidth + spacing))
            .floor()
            .clamp(1, maxColumns);
        final width = (box.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              children.map((w) => SizedBox(width: width, child: w)).toList(),
        );
      });
}

class Fact extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const Fact(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OipTokens.s2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: 9, letterSpacing: .75)),
          const SizedBox(height: OipTokens.s1),
          Semantics(
            label: value,
            excludeSemantics: true,
            child: SelectableText(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: valueColor)),
          ),
        ]),
      );
}

class FactGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  const FactGrid({super.key, required this.children, this.minWidth = 210});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= minWidth * 2 + OipTokens.s4 ? 2 : 1;
        if (columns == 1) return Column(children: children);
        final width = (box.maxWidth - OipTokens.s4) / 2;
        return Wrap(
            spacing: OipTokens.s4,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList());
      });
}

class StateMessage extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Widget? action;
  final bool compact;
  const StateMessage(this.title, this.message,
      {super.key,
      this.icon = Icons.info_outline,
      this.action,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon,
          size: compact ? 24 : 30,
          color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: OipTokens.s3),
      Text(title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center),
      const SizedBox(height: OipTokens.s2),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ),
      if (action != null)
        Padding(
            padding: const EdgeInsets.only(top: OipTokens.s2), child: action),
    ]);
    return Panel(
        padding: EdgeInsets.all(compact ? OipTokens.s4 : OipTokens.s6),
        child: Center(child: content));
  }
}

class InlineNotice extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Color? color;
  const InlineNotice(this.title, this.message,
      {super.key, this.icon = Icons.info_outline, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(
        context, color ?? Theme.of(context).colorScheme.primary);
    return Container(
      padding: const EdgeInsets.all(OipTokens.s3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [tone.withOpacity(.12), tone.withOpacity(.045)]),
        borderRadius: BorderRadius.circular(OipTokens.radiusSm),
        border: Border.all(color: tone.withOpacity(.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: tone),
        const SizedBox(width: OipTokens.s3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: tone)),
            const SizedBox(height: OipTokens.s1),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// Hover/focus treatment for inspector panels; content remains fully readable.
class InteractiveInspector extends StatefulWidget {
  final Widget child;
  final Color accent;
  final VoidCallback? onTap;
  const InteractiveInspector(
      {super.key, required this.child, required this.accent, this.onTap});

  @override
  State<InteractiveInspector> createState() => _InteractiveInspectorState();
}

class _InteractiveInspectorState extends State<InteractiveInspector> {
  bool active = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return GradientCard(accent: widget.accent, child: widget.child);
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return MouseRegion(
      onEnter: (_) => setState(() => active = true),
      onExit: (_) => setState(() => active = false),
      child: FocusableActionDetector(
        onFocusChange: (value) => setState(() => active = value),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : OipTokens.motion,
          transform: Matrix4.identity()
            ..translate(0.0, active && widget.onTap != null ? -1.0 : 0.0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(OipTokens.radius),
              child: GradientCard(accent: widget.accent, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class SpectrumTimelineEntry {
  final String id, track, label, detail;
  final int? atMs;
  final Color color;
  const SpectrumTimelineEntry(
      {required this.id,
      required this.track,
      required this.label,
      required this.detail,
      required this.color,
      this.atMs});
}

/// A compact DAW-inspired visualisation of actual timestamped API events.
class DataTimeline extends StatelessWidget {
  final List<SpectrumTimelineEntry> entries;
  final String? selectedId;
  final ValueChanged<SpectrumTimelineEntry>? onSelected;
  const DataTimeline(
      {super.key, required this.entries, this.selectedId, this.onSelected});

  @override
  Widget build(BuildContext context) {
    final valid = entries.where((entry) => entry.atMs != null).toList();
    if (valid.isEmpty) {
      return InlineNotice(
          context.tr("Keine zeitgestempelten Ereignisse"),
          context.tr(
              "Die API hat keine darstellbaren Collection-Zeitpunkte geliefert."));
    }
    final tracks = valid.map((entry) => entry.track).toSet().toList();
    final first = valid.map((entry) => entry.atMs!).reduce(math.min);
    final last = valid.map((entry) => entry.atMs!).reduce(math.max);
    final span = math.max(1, last - first);
    return Semantics(
      label:
          context.tr("Ereignis-Zeitspuren, {0} API-Ereignisse", [valid.length]),
      child: Column(children: [
        LayoutBuilder(builder: (context, box) {
          final labelWidth = box.maxWidth < 420 ? 76.0 : 112.0;
          return Column(children: [
            for (final track in tracks)
              SizedBox(
                height: 64,
                child: Row(children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(track.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, lane) {
                      final laneEntries =
                          valid.where((entry) => entry.track == track).toList();
                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .scaffoldBackgroundColor
                              .withOpacity(.55),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Stack(children: [
                          for (final entry in laneEntries)
                            Positioned(
                              left: ((entry.atMs! - first) /
                                      span *
                                      (lane.maxWidth - 40))
                                  .clamp(
                                      0.0, math.max(0.0, lane.maxWidth - 40)),
                              top: 10,
                              width: 40,
                              height: 42,
                              child: Tooltip(
                                message: '${entry.label}\n${entry.detail}',
                                child: Semantics(
                                  button: true,
                                  label:
                                      '${entry.track}: ${entry.label}, ${timestamp(entry.atMs)}',
                                  child: Material(
                                    color: selectedId == entry.id
                                        ? entry.color
                                        : entry.color.withOpacity(.72),
                                    borderRadius: BorderRadius.circular(7),
                                    child: InkWell(
                                      key: Key('timeline-${entry.id}'),
                                      onTap: onSelected == null
                                          ? null
                                          : () => onSelected!(entry),
                                      borderRadius: BorderRadius.circular(7),
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          border: Border.all(
                                              color: selectedId == entry.id
                                                  ? Colors.white
                                                  : entry.color,
                                              width: selectedId == entry.id
                                                  ? 1.5
                                                  : 1),
                                        ),
                                        child: Icon(
                                            entry.label.contains('verloren')
                                                ? Icons.link_off
                                                : Icons.bolt,
                                            size: 16,
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? const Color(0xff0b0d14)
                                                    : Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      );
                    }),
                  ),
                ]),
              ),
          ]);
        }),
        const SizedBox(height: OipTokens.s2),
        Row(children: [
          Expanded(
              child: Text(timestamp(first),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(timestamp(last),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ]),
    );
  }
}

/// The icon of a device.
///
/// The vocabulary of the type of a device has **one** owner
/// (`widgets/device_kind.dart`): the Core paints the type of a device as the
/// identifier of its own enum, and every type that the Core can really
/// deliver gets an icon of its own.
IconData deviceIcon(String kind) => deviceKindIcon(kind);

String known(String? value) => OipTokens.statusLabel(value);

String timestamp(int? ms) {
  if (ms == null) return 'Unbekannt';
  final value = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.'
      '${value.millisecond.toString().padLeft(3, '0')} UTC';
}
