import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../widgets/workstation.dart';

/// The flat, tightly framed panel chrome of a monitoring dashboard: a title
/// row with the state of the signal and the visualisation below.
class DashboardPanelFrame extends StatelessWidget {
  static const radius = 5.0;

  final String title;
  final String? subtitle;
  final String? tooltip;
  final Color? stateColor;
  final String? badge;
  final List<Widget> actions;
  final Widget child;
  final double? height;

  const DashboardPanelFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.tooltip,
    this.stateColor,
    this.badge,
    this.actions = const [],
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final header = Row(children: [
      if (stateColor != null) ...[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
        ),
        const SizedBox(width: 7),
      ],
      Flexible(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Expanded(
          child: Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.mono(context,
                  size: 10, color: OipTokens.muted(context))),
        ),
      ] else
        const Spacer(),
      if (badge != null && stateColor != null)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: stateColor!.withOpacity(.12),
            border: Border.all(color: stateColor!.withOpacity(.4)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(badge!,
              style: WorkstationTokens.mono(context,
                  size: 9, color: stateColor, weight: FontWeight.w700)),
        ),
      ...actions,
    ]);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: WorkstationTokens.panel(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: tooltip == null
                  ? header
                  : Tooltip(
                      message: tooltip!,
                      waitDuration: const Duration(milliseconds: 500),
                      child: header),
            ),
          ),
          if (height == null) child else Expanded(child: child),
        ],
      ),
    );
  }
}
