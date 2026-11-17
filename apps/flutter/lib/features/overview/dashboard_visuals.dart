part of 'dashboard_workspace.dart';

List<double> _numbers(List<Observation> samples) => [
      for (final sample in samples)
        if (sample.number != null) sample.number!,
    ];

TextStyle _boundsStyle(BuildContext context) =>
    WorkstationTokens.mono(context, size: 10, color: OipTokens.muted(context));

class _Collecting extends StatelessWidget {
  const _Collecting();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Sammle Sitzungswerte …',
            style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Shared layout of the session charts: current value on top, the chart in
/// the remaining space and an optional caption below.
class _ChartTile extends StatelessWidget {
  final Observation item;
  final Color color;
  final Widget chart;
  final Widget? footer;
  const _ChartTile({
    required this.item,
    required this.color,
    required this.chart,
    this.footer,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _ValueText(item: item, color: color, size: 24),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: chart),
            if (footer != null) ...[const SizedBox(height: 5), footer!],
          ],
        ),
      );
}

// ── Füllstand ───────────────────────────────────────────────────────────────

class _TankBody extends StatelessWidget {
  final Observation item;
  final double value;
  final _Scale scale;
  final Color color;
  const _TankBody({
    required this.item,
    required this.value,
    required this.scale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = _boundsStyle(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 74,
            child: CustomPaint(
              painter: _TankPainter(
                fraction: scale.fraction(value),
                color: color,
                outline: WorkstationTokens.line(context),
                track: WorkstationTokens.hairline(context),
                marks: [
                  for (final band in _bands(scale))
                    if (band.from > 0)
                      (at: band.from, color: _levelColor(context, band.level)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatBound(scale.max, item), style: bounds),
                _ValueText(item: item, color: color, size: 34),
                Text(
                    scale.auto
                        ? '${_formatBound(scale.min, item)} · Skala automatisch'
                        : _formatBound(scale.min, item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bounds),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TankPainter extends CustomPainter {
  final double fraction;
  final Color color, outline, track;
  final List<({double at, Color color})> marks;
  const _TankPainter({
    required this.fraction,
    required this.color,
    required this.outline,
    required this.track,
    required this.marks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 12 || size.height <= 0) return;
    final vessel = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width - 12, size.height),
        const Radius.circular(7));
    canvas.drawRRect(vessel, Paint()..color = track.withOpacity(.4));
    canvas.save();
    canvas.clipRRect(vessel);
    final level = size.height * (1 - fraction);
    canvas.drawRect(
      Rect.fromLTRB(0, level, vessel.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withOpacity(.55)],
        ).createShader(Rect.fromLTRB(0, level, vessel.width, size.height)),
    );
    // Quarter graduations.
    final tick = Paint()
      ..color = outline.withOpacity(.7)
      ..strokeWidth = 1;
    for (var quarter = 1; quarter < 4; quarter++) {
      final y = size.height * quarter / 4;
      canvas.drawLine(Offset(0, y), Offset(vessel.width * .22, y), tick);
    }
    canvas.restore();
    canvas.drawRRect(
        vessel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = outline);
    for (final mark in marks) {
      final y = size.height * (1 - mark.at);
      canvas.drawLine(
          Offset(size.width - 9, y),
          Offset(size.width, y),
          Paint()
            ..color = mark.color
            ..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _TankPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.outline != outline ||
      old.marks.length != marks.length;
}

// ── Linie / Säulen ──────────────────────────────────────────────────────────

class _SeriesBody extends StatelessWidget {
  final Observation item;
  final List<Observation> samples;
  final Color color;
  final bool bars;
  const _SeriesBody({
    required this.item,
    required this.samples,
    required this.color,
    required this.bars,
  });

  @override
  Widget build(BuildContext context) {
    final values = _numbers(samples);
    if (values.length < 2) {
      return _ChartTile(item: item, color: color, chart: const _Collecting());
    }
    final top = values.reduce(math.max);
    final low = values.reduce(math.min);
    // Columns grow from zero so their height stays comparable.
    final base = bars ? math.min(0.0, low) : low;
    return _ChartTile(
      item: item,
      color: color,
      chart: CustomPaint(
        painter: _SeriesPainter(
          values: values,
          base: base,
          top: top,
          color: color,
          bars: bars,
          grid: WorkstationTokens.hairline(context),
          labelStyle:
              DefaultTextStyle.of(context).style.merge(_boundsStyle(context)),
          topLabel: _formatBound(top, item),
          baseLabel: _formatBound(base, item),
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  final List<double> values;
  final double base, top;
  final Color color, grid;
  final bool bars;
  final TextStyle labelStyle;
  final String topLabel, baseLabel;
  _SeriesPainter({
    required List<double> values,
    required this.base,
    required this.top,
    required this.color,
    required this.bars,
    required this.grid,
    required this.labelStyle,
    required this.topLabel,
    required this.baseLabel,
  }) : values = List.of(values);

  void _label(Canvas canvas, String text, Offset at, {bool below = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, at - Offset(0, below ? 0 : painter.height));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 8) return;
    const inset = 3.0;
    final height = size.height - inset * 2;
    final range = top - base;
    double y(double value) =>
        inset + height - (range == 0 ? .5 : (value - base) / range) * height;

    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var step = 0; step <= 3; step++) {
      final gy = inset + height * step / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), line);
    }

    if (bars) {
      final slot = size.width / values.length;
      final width = math.max(1.0, slot - (slot > 4 ? 2 : 0));
      final paint = Paint()..color = color.withOpacity(.85);
      for (var index = 0; index < values.length; index++) {
        final top = math.min(y(values[index]), inset + height - 1.5);
        canvas.drawRect(
            Rect.fromLTRB(
                index * slot, top, index * slot + width, inset + height),
            paint);
      }
    } else {
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final x = size.width * index / (values.length - 1);
        if (index == 0) {
          path.moveTo(x, y(values[index]));
        } else {
          path.lineTo(x, y(values[index]));
        }
      }
      final area = Path.from(path)
        ..lineTo(size.width, inset + height)
        ..lineTo(0, inset + height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(.30), color.withOpacity(.02)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(
          Offset(size.width - 2, y(values.last)), 2.6, Paint()..color = color);
    }
    _label(canvas, topLabel, const Offset(2, inset + 1), below: true);
    _label(canvas, baseLabel, Offset(2, inset + height - 1));
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) => true;
}

// ── Histogramm ──────────────────────────────────────────────────────────────

class _HistogramBody extends StatelessWidget {
  static const bins = 12;

  final Observation item;
  final List<Observation> samples;
  final Color color;
  const _HistogramBody(
      {required this.item, required this.samples, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = _numbers(samples);
    if (values.length < 2) {
      return _ChartTile(item: item, color: color, chart: const _Collecting());
    }
    final low = values.reduce(math.min);
    final top = values.reduce(math.max);
    final counts = List.filled(bins, 0);
    for (final value in values) {
      final index = top == low
          ? bins ~/ 2
          : (((value - low) / (top - low)) * bins).floor().clamp(0, bins - 1);
      counts[index]++;
    }
    final bounds = _boundsStyle(context);
    return _ChartTile(
      item: item,
      color: color,
      chart: CustomPaint(
        painter: _HistogramPainter(
            counts, color, WorkstationTokens.hairline(context)),
      ),
      footer: Row(children: [
        Text(_formatBound(low, item), style: bounds),
        Expanded(
          child: Text('Verteilung · ${values.length} Samples',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bounds),
        ),
        Text(_formatBound(top, item), style: bounds),
      ]),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> counts;
  final Color color, base;
  const _HistogramPainter(this.counts, this.color, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 2) return;
    final most = counts.reduce(math.max);
    const gap = 2.0;
    final width = (size.width - gap * (counts.length - 1)) / counts.length;
    for (var index = 0; index < counts.length; index++) {
      final left = index * (width + gap);
      final height = most == 0 ? 0.0 : (size.height - 1) * counts[index] / most;
      canvas.drawRect(Rect.fromLTWH(left, size.height - 1, width, 1),
          Paint()..color = base);
      if (height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
              Rect.fromLTWH(left, size.height - 1 - height, width, height),
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2)),
          Paint()..color = color.withOpacity(.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) => true;
}

// ── Zustand (State timeline / Heat strip) ───────────────────────────────────

class _TimelineBody extends StatelessWidget {
  final Observation item;
  final List<Observation> samples;
  final _Scale scale;
  final Color color;
  const _TimelineBody({
    required this.item,
    required this.samples,
    required this.scale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final values = _numbers(samples);
    if (values.isEmpty) {
      return _ChartTile(item: item, color: color, chart: const _Collecting());
    }
    final thresholds = scale.warn != null || scale.crit != null;
    final low = values.reduce(math.min);
    final top = values.reduce(math.max);
    final base = _levelColor(context, null);
    final counts = [0, 0, 0];
    final cells = <Color>[];
    for (final value in values) {
      if (thresholds) {
        final level = scale.level(value)!;
        counts[level]++;
        cells.add(_levelColor(context, level));
      } else {
        // Without thresholds the strip is a heat strip over the session span.
        final share = top == low ? 1.0 : (value - low) / (top - low);
        cells.add(base.withOpacity(.18 + .82 * share));
      }
    }
    String share(int count) => '${(100 * count / values.length).round()} %';
    final bounds = _boundsStyle(context);
    return _ChartTile(
      item: item,
      color: color,
      chart: Center(
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: CustomPaint(painter: _TimelinePainter(cells)),
        ),
      ),
      footer: Text(
          thresholds
              ? 'Normal ${share(counts[0])} · Warnung ${share(counts[1])} · Kritisch ${share(counts[2])}'
              : 'Intensität: ${_formatBound(low, item)} – ${_formatBound(top, item)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bounds),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<Color> cells;
  const _TimelinePainter(this.cells);

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty || size.width <= 0) return;
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)));
    final slot = size.width / cells.length;
    final gap = slot > 6 ? 1.0 : 0.0;
    for (var index = 0; index < cells.length; index++) {
      canvas.drawRect(
          Rect.fromLTWH(index * slot, 0, slot - gap + .5, size.height),
          Paint()..color = cells[index]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => true;
}

// ── Statistik ───────────────────────────────────────────────────────────────

class _StatsBody extends StatelessWidget {
  final Observation item;
  final double value;
  final List<Observation> samples;
  final Color color;
  const _StatsBody({
    required this.item,
    required this.value,
    required this.samples,
    required this.color,
  });

  Widget _cell(BuildContext context, String label, double? value,
          {Color? tone}) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: WorkstationTokens.well(context),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: _boundsStyle(context)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value == null ? '–' : _formatBound(value, item),
                    maxLines: 1,
                    style: _valueStyle(context,
                        tone ?? Theme.of(context).colorScheme.onSurface, 19)),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final values = _numbers(samples);
    final has = values.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
      child: Column(children: [
        Expanded(
          child: Row(children: [
            _cell(context, 'AKTUELL', value, tone: color),
            _cell(context, 'Ø SITZUNG',
                has ? values.reduce((a, b) => a + b) / values.length : null),
          ]),
        ),
        Expanded(
          child: Row(children: [
            _cell(context, 'MIN', has ? values.reduce(math.min) : null),
            _cell(context, 'MAX', has ? values.reduce(math.max) : null),
          ]),
        ),
      ]),
    );
  }
}

// ── Tabelle / Vergleich ─────────────────────────────────────────────────────

class _BarRow extends StatelessWidget {
  final String label, value;
  final double? fraction;
  final Color color;
  final Color? state;
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    this.state,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: Row(children: [
          if (state != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: state),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 5,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context, size: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: fraction == null
                ? const SizedBox.shrink()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 10,
                      color:
                          WorkstationTokens.hairline(context).withOpacity(.55),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction!.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(color: color),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 82,
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context,
                    size: 11.5, color: color, weight: FontWeight.w700)),
          ),
        ]),
      );
}

Widget _rows(BuildContext context, List<Widget> rows, int hidden,
        {String? caption}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: WorkstationTokens.hairline(context).withOpacity(.6)),
            rows[index],
          ],
          if (hidden > 0 || caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  [
                    if (caption != null) caption,
                    if (hidden > 0) '+$hidden weitere nicht dargestellt',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );

const _maxRows = 12;

/// Every signal of the device the anchor signal belongs to.
class _TableBody extends StatelessWidget {
  final Observation anchor;
  final List<Observation> all;
  final Map<String, List<Observation>> session;
  const _TableBody(
      {required this.anchor, required this.all, required this.session});

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final rows = [
      for (final item in all)
        if (item.sourceId == anchor.sourceId &&
            item.entityId == anchor.entityId &&
            seen.add(observationKey(item)))
          item,
    ];
    return _rows(
      context,
      [
        for (final item in rows.take(_maxRows))
          Builder(builder: (context) {
            final key = observationKey(item);
            final number = item.number;
            final fresh = item.freshness == 'fresh';
            final scale = _resolveScale(_PanelSpec(key, _PanelKind.bar), item,
                session[key] ?? const []);
            return _BarRow(
              label: item.metricId,
              value: number == null ? item.display : _formatBound(number, item),
              // A bar needs a meaningful range; a scale guessed from the
              // value itself would only mirror that value.
              fraction:
                  number == null || scale.auto ? null : scale.fraction(number),
              color: !fresh || number == null
                  ? OipTokens.muted(context)
                  : _levelColor(context, scale.level(number)),
              state: OipTokens.statusColor(context, item.freshness),
            );
          }),
      ],
      rows.length - math.min(rows.length, _maxRows),
    );
  }
}

/// The same metric across every device that delivers it in this context.
class _CompareBody extends StatelessWidget {
  final _PanelSpec spec;
  final String metricId;
  final List<Observation> all;
  const _CompareBody(
      {required this.spec, required this.metricId, required this.all});

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final rows = [
      for (final item in all)
        if (item.metricId == metricId &&
            item.number != null &&
            seen.add(observationKey(item)))
          item,
    ]..sort((a, b) => b.number!.compareTo(a.number!));
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Text('Kein Gerät liefert diese Metrik in diesem Kontext.',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final scale = _resolveScale(spec, rows.first, rows);
    return _rows(
      context,
      [
        for (final item in rows.take(_maxRows))
          _BarRow(
            label: item.entityId,
            value: _formatBound(item.number!, item),
            fraction: scale.fraction(item.number!),
            color: item.freshness == 'fresh'
                ? _levelColor(context, scale.level(item.number!))
                : OipTokens.muted(context),
            state: OipTokens.statusColor(context, item.freshness),
          ),
      ],
      rows.length - math.min(rows.length, _maxRows),
      caption:
          'Skala ${_formatBound(scale.min, rows.first)} – ${_formatBound(scale.max, rows.first)}',
    );
  }
}

// ── Gerätestatus ────────────────────────────────────────────────────────────

class _DevicesBody extends StatelessWidget {
  static const _max = 60;
  final List<Device> devices;
  const _DevicesBody({required this.devices});

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Text('Für diesen Kontext wurden keine Geräte geliefert.',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final device in devices.take(_max))
              Builder(builder: (context) {
                final health = device.health;
                final tone =
                    OipTokens.statusColor(context, health.reachability);
                return Tooltip(
                  message: '${device.name}\n'
                      'Erreichbarkeit ${OipTokens.statusLabel(health.reachability)} · '
                      'Dienst ${OipTokens.statusLabel(health.service)} · '
                      'Telemetrie ${OipTokens.statusLabel(health.freshness)}',
                  child: Container(
                    width: 156,
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: tone.withOpacity(.13),
                      border: Border.all(color: tone.withOpacity(.45)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(OipTokens.statusIcon(health.reachability),
                          size: 16, color: tone),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                            Text(OipTokens.statusLabel(health.reachability),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WorkstationTokens.mono(context,
                                    size: 10, color: tone)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              }),
          ]),
          if (devices.length > _max)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+${devices.length - _max} weitere nicht dargestellt',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

// ── Abschnitt ───────────────────────────────────────────────────────────────

class _HeadingPanel extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const _HeadingPanel({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: Row(children: [
          const Icon(Icons.expand_more, size: 18),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Divider(height: 1, color: WorkstationTokens.hairline(context)),
          ),
          ...actions,
        ]),
      );
}
