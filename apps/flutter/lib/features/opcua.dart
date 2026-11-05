import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/controller.dart';
import '../services/api.dart';
import '../models/contracts.dart';
import '../design_system/theme.dart';
import '../widgets/components.dart';

class OpcuaPage extends StatefulWidget {
  final OipController controller;
  const OpcuaPage(this.controller, {super.key});

  @override
  State<OpcuaPage> createState() => _OpcuaPageState();
}

class _OpcuaPageState extends State<OpcuaPage> {
  NodePage? page;
  OpcNode? selected;
  String search = '', folder = 'M-01';
  String? error;
  bool loading = false;
  int offset = 0, generation = 0;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gen = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.controller.api.nodes(search, folder, offset);
      if (!mounted || gen != generation) return;
      setState(() {
        page = result;
        selected =
            result.items.where((item) => item.id == selected?.id).firstOrNull ??
                result.items.firstOrNull;
        loading = false;
      });
    } catch (exception) {
      if (mounted && gen == generation) {
        setState(() {
          error = apiErrorMessage(exception,
              'OPC-UA-Nodes konnten nicht geladen werden. Bitte erneut versuchen.');
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    final node = selected;
    final live = node == null
        ? null
        : snapshot.metrics
            .where((item) =>
                snapshot.primarySourceId != null &&
                item.sourceId == snapshot.primarySourceId &&
                item.entityId == 'M-01' &&
                item.metricId == node.name)
            .firstOrNull;
    final cached = node?.observation;
    final observation =
        live ?? (cached?.sourceId == snapshot.primarySourceId ? cached : null);
    final alarm = snapshot.hasAlarm(deviceId: 'M-01');
    final pageSize = page == null || page!.limit <= 0 ? 40 : page!.limit;

    final namespace = GradientCard(
      accent: OipTokens.violet,
      padding: const EdgeInsets.all(OipTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccentHeader(
            'Namespace 2',
            'urn:oip:local-simulation',
            accent: OipTokens.violet,
            icon: Icons.account_tree_outlined,
          ),
          Text('ADRESSRAUM', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: OipTokens.s2),
          Wrap(
            spacing: OipTokens.s2,
            runSpacing: OipTokens.s2,
            children: ['M-01', 'Bulk', 'all']
                .map((value) => ChoiceChip(
                      key: Key('folder-$value'),
                      avatar: Icon(
                        value == 'M-01'
                            ? Icons.precision_manufacturing_outlined
                            : value == 'Bulk'
                                ? Icons.dataset_outlined
                                : Icons.account_tree_outlined,
                        size: 16,
                        color: folder == value
                            ? OipTokens.readableAccent(
                                context, OipTokens.violet)
                            : OipTokens.muted(context),
                      ),
                      label: Text(value == 'all' ? 'Alle' : value),
                      materialTapTargetSize:
                          MediaQuery.sizeOf(context).width < OipTokens.mobile
                              ? MaterialTapTargetSize.padded
                              : MaterialTapTargetSize.shrinkWrap,
                      selected: folder == value,
                      onSelected: (_) {
                        setState(() {
                          folder = value;
                          offset = 0;
                        });
                        _load();
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: OipTokens.s4),
          Container(
            padding: const EdgeInsets.all(OipTokens.s3),
            decoration: BoxDecoration(
              color: OipTokens.cyan.withOpacity(.07),
              borderRadius: BorderRadius.circular(OipTokens.radiusSm),
              border: Border.all(color: OipTokens.cyan.withOpacity(.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AKTIVE QUELLE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: OipTokens.categoryColor(context, 'sensor'))),
                const SizedBox(height: OipTokens.s1),
                Text(snapshot.primarySourceId ?? 'Unbekannt',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(
                    'Namespace 2  /  ${folder == 'all' ? 'Alle Ordner' : folder}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: OipTokens.s4),
          const InlineNotice(
            'Read-only Explorer',
            'Kein Schreibzugriff. Werte und Zeitstempel kommen aus dem Rust-Adapter.',
            icon: Icons.lock_outline,
            color: OipTokens.violet,
          ),
        ],
      ),
    );

    final nodeList = GradientCard(
      accent: OipTokens.cyan,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccentHeader(
            'Node-Liste',
            'Seitenweise API-Ergebnisse · max. 40 Einträge pro Ansicht',
            accent: OipTokens.cyan,
            icon: Icons.list_alt_outlined,
          ),
          TextField(
            key: const Key('node-search'),
            decoration: const InputDecoration(
                hintText: 'Nodes durchsuchen',
                prefixIcon: Icon(Icons.search, size: 18)),
            onChanged: (value) {
              search = value;
              offset = 0;
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            StateMessage('Browser nicht verfügbar', error!,
                compact: true,
                action: TextButton(
                    onPressed: _load, child: const Text('Erneut versuchen'))),
          if (!loading && error == null && page?.items.isEmpty == true)
            const StateMessage(
                'Keine Nodes', 'Suche ändern oder Collector-Verbindung prüfen.',
                compact: true),
          const SizedBox(height: OipTokens.s3),
          SizedBox(
            height: 430,
            child: ListView.separated(
              key: const Key('node-list'),
              itemCount: page?.items.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final item = page!.items[index];
                final active = selected?.id == item.id;
                return Material(
                  color: active
                      ? OipTokens.violet.withOpacity(.15)
                      : index.isEven
                          ? OipTokens.cyan.withOpacity(.025)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(OipTokens.radiusSm),
                  child: ListTile(
                    key: Key('node-${item.name}'),
                    dense: true,
                    selected: active,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(OipTokens.radiusSm),
                      side: BorderSide(
                          color: active
                              ? OipTokens.violet.withOpacity(.55)
                              : Colors.transparent),
                    ),
                    leading: Icon(_nodeIcon(item.dataType),
                        size: 17,
                        color: OipTokens.readableAccent(context,
                            active ? OipTokens.violet : OipTokens.cyan)),
                    title: Text(item.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.dataType,
                        style: Theme.of(context).textTheme.bodySmall),
                    trailing: active
                        ? Icon(Icons.chevron_right,
                            size: 16,
                            color: OipTokens.readableAccent(
                                context, OipTokens.violet))
                        : null,
                    onTap: () => setState(() => selected = item),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                    '${page?.total ?? 0} Nodes · Seite ${(page?.offset ?? offset) ~/ pageSize + 1}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              IconButton(
                tooltip: 'Vorherige Nodes',
                onPressed: loading || offset == 0
                    ? null
                    : () {
                        offset = (offset - pageSize).clamp(0, offset).toInt();
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const Key('next-nodes'),
                tooltip: 'Nächste Nodes',
                onPressed: loading || offset + pageSize >= (page?.total ?? 0)
                    ? null
                    : () {
                        offset += pageSize;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );

    final detail = node == null
        ? const StateMessage(
            'Node auswählen', 'Wähle eine Variable aus dem Adressraum.')
        : InteractiveInspector(
            accent: OipTokens.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccentHeader(
                  node.name,
                  '${node.folder} / Namespace ${node.namespace}',
                  accent: OipTokens.violet,
                  icon: _nodeIcon(node.dataType),
                  action: StatusPill(known(observation?.quality),
                      color:
                          OipTokens.statusColor(context, observation?.quality),
                      showDot: true),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _nodeValue(node, observation),
                        key: const Key('node-value'),
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: alarm && node.name == 'temperature'
                                      ? OipTokens.statusColor(context, 'alarm')
                                      : observation == null
                                          ? OipTokens.muted(context)
                                          : OipTokens.categoryColor(
                                              context, 'sensor'),
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'NodeId kopieren',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: node.id));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('NodeId kopiert')),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: OipTokens.s3),
                Wrap(
                  spacing: OipTokens.s2,
                  runSpacing: OipTokens.s2,
                  children: [
                    StatusPill(
                        snapshot.system.simulated
                            ? 'OPC-UA-SIMULATOR'
                            : 'OPC-UA-API',
                        color: OipTokens.statusColor(context, 'info'),
                        icon: snapshot.system.simulated
                            ? Icons.science_outlined
                            : Icons.cloud_done_outlined),
                    StatusPill(
                      widget.controller.stale
                          ? 'Veraltet'
                          : live != null
                              ? known(observation!.freshness)
                              : 'Einzelabfrage',
                      color: widget.controller.stale
                          ? OipTokens.statusColor(context, 'degraded')
                          : OipTokens.statusColor(
                              context, observation?.freshness),
                      showDot: true,
                    ),
                  ],
                ),
                const SizedBox(height: OipTokens.s4),
                FactGrid(
                  children: [
                    Fact('NodeId', node.id),
                    Fact('Datentyp / Zugriff',
                        '${node.dataType} / ${node.access}'),
                    Fact('SourceTimestamp · virtuelle Quellzeit',
                        timestamp(observation?.sourceMs)),
                    Fact('ServerTimestamp', timestamp(observation?.serverMs)),
                    Fact('ReceivedTimestamp · lokale Empfangszeit',
                        timestamp(observation?.receivedMs)),
                    Fact('Quality / StatusCode',
                        '${observation?.quality ?? 'unknown'} / ${observation?.statusCode?.toString() ?? 'unbekannt'}'),
                    Fact('CollectionError',
                        observation?.collectionError ?? 'Keine gemeldet'),
                    Fact(
                        'Subscription',
                        live != null
                            ? known(snapshot.system.subscription)
                            : 'Nicht abonniert · gezielte API-Einzelabfrage'),
                  ],
                ),
                const SizedBox(height: OipTokens.s3),
                const InlineNotice(
                  'Lesender Adressraumzugriff',
                  'Sechs Prozessvariablen werden fortlaufend abonniert. Bulk-Nodes werden seitenweise über den Rust-Adapter gelesen und in SQLite persistiert. Kein Schreibzugriff.',
                  icon: Icons.lock_outline,
                  color: OipTokens.violet,
                ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('OPC-UA-Browser',
            '${snapshot.system.simulated ? 'Lokaler Simulationsserver' : 'OPC-UA-Server'} · read-only · ${known(snapshot.system.opcua)}',
            accent: OipTokens.violet,
            action: IconButton(
                tooltip: 'Nodes aktualisieren',
                onPressed: _load,
                icon: const Icon(Icons.refresh))),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth >= OipTokens.workstation) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 220, child: namespace),
              const SizedBox(width: OipTokens.s4),
              SizedBox(width: 350, child: nodeList),
              const SizedBox(width: OipTokens.s4),
              Expanded(child: detail),
            ]);
          }
          if (box.maxWidth >= OipTokens.tablet) {
            return Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 240, child: namespace),
                const SizedBox(width: OipTokens.s4),
                Expanded(child: nodeList),
              ]),
              const SizedBox(height: OipTokens.s4),
              detail,
            ]);
          }
          return Column(children: [
            namespace,
            const SizedBox(height: OipTokens.s4),
            nodeList,
            const SizedBox(height: OipTokens.s4),
            detail,
          ]);
        }),
      ],
    );
  }

  IconData _nodeIcon(String dataType) {
    if (dataType.contains('Double') || dataType.contains('Int')) {
      return Icons.numbers;
    }
    if (dataType.contains('Boolean')) return Icons.toggle_on_outlined;
    if (dataType.contains('String')) return Icons.text_fields;
    return Icons.data_object;
  }

  String _nodeValue(OpcNode node, Observation? observation) {
    final value = observation?.display ?? 'Unbekannt';
    final symbol = observation?.symbol ?? '';
    if (node.folder != 'Bulk' || observation?.number == null) {
      return '$value $symbol'.trim();
    }
    if (value.contains('e') || value.contains('E')) {
      return '$value $symbol'.trim();
    }
    final parts = value.split('.');
    final grouped = parts.first.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.');
    return '${parts.length > 1 ? '$grouped,${parts.last}' : grouped} $symbol'
        .trim();
  }
}
