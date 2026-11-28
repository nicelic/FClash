import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrackerInfoItem extends StatelessWidget {
  final TrackerInfo trackerInfo;
  final Function(String)? onClickKeyword;
  final Widget? trailing;
  final String detailTitle;
  final ValueListenable<TrackerInfosState>? detailStateListenable;
  final ValueListenable<int>? relativeTimeListenable;
  final bool? showProcess;
  @visibleForTesting
  final bool? supportsProcessIcon;

  const TrackerInfoItem({
    super.key,
    required this.trackerInfo,
    this.onClickKeyword,
    this.trailing,
    required this.detailTitle,
    this.detailStateListenable,
    this.relativeTimeListenable,
    this.showProcess,
    this.supportsProcessIcon,
  });

  Widget _buildMeta(BuildContext context, {required bool showProcessText}) {
    final chains = trackerInfo.chains;
    final process = showProcessText ? trackerInfo.metadata.process.trim() : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrackerMetaText(
          trackerInfo: trackerInfo,
          relativeTimeListenable: relativeTimeListenable,
        ),
        if (chains.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final chain in chains)
                  CommonChip(
                    label: chain,
                    onPressed: () => onClickKeyword?.call(chain),
                  ),
              ],
            ),
          ),
        if (process.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: chains.isNotEmpty ? 4 : 2),
            child: Text(
              process,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, {required bool showProcess}) {
    final canShowIcon = supportsProcessIcon ?? system.isAndroid;
    final showIcon = showProcess && canShowIcon;
    final showProcessText = showProcess && !canShowIcon;
    final process = trackerInfo.metadata.process.trim();
    final icon = showIcon
        ? GestureDetector(
            onTap: () {
              if (process.isEmpty) return;
              onClickKeyword?.call(process);
            },
            child: Padding(
              padding: const EdgeInsetsGeometry.only(top: 6),
              child: PackageIcon(packageName: process, size: 44),
            ),
          )
        : null;
    return ListItem(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ).copyWith(bottom: 12),
      minVerticalPadding: 0,
      horizontalTitleGap: 12,
      tileTitleAlignment: ListTileTitleAlignment.top,
      onTap: () {
        showExtend(
          context,
          builder: (_) {
            return AdaptiveSheetScaffold(
              sheetTransparentToolBar: true,
              body: TrackerInfoDetailView(
                trackerInfo: trackerInfo,
                stateListenable: detailStateListenable,
              ),
              title: detailTitle,
            );
          },
        );
      },
      leading: icon,
      title: Text(
        trackerInfo.desc,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodyLarge,
      ),
      subtitle: _buildMeta(context, showProcessText: showProcessText),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final explicitShowProcess = showProcess;
    if (explicitShowProcess != null) {
      return _buildTile(context, showProcess: explicitShowProcess);
    }
    return Consumer(
      builder: (context, ref, _) {
        final resolvedShowProcess = ref.watch(
          patchClashConfigProvider.select(
            (state) => state.findProcessMode == FindProcessMode.always,
          ),
        );
        return _buildTile(context, showProcess: resolvedShowProcess);
      },
    );
  }
}

class _TrackerMetaText extends StatelessWidget {
  final TrackerInfo trackerInfo;
  final ValueListenable<int>? relativeTimeListenable;

  const _TrackerMetaText({
    required this.trackerInfo,
    this.relativeTimeListenable,
  });

  Widget _buildText(BuildContext context) {
    final metaText =
        '${trackerInfo.start.getLastUpdateTimeDesc(context)} · ${trackerInfo.trafficSummary}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        metaText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenable = relativeTimeListenable;
    if (listenable == null) {
      return _buildText(context);
    }
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, _, _) => _buildText(context),
    );
  }
}

class TrackerInfoDetailView extends StatefulWidget {
  final TrackerInfo trackerInfo;
  final ValueListenable<TrackerInfosState>? stateListenable;

  const TrackerInfoDetailView({
    super.key,
    required this.trackerInfo,
    this.stateListenable,
  });

  @override
  State<TrackerInfoDetailView> createState() => _TrackerInfoDetailViewState();
}

class _TrackerInfoDetailViewState extends State<TrackerInfoDetailView> {
  late TrackerInfo _trackerInfo = widget.trackerInfo;

  @override
  void initState() {
    super.initState();
    _syncFromListenable(notify: false);
    widget.stateListenable?.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant TrackerInfoDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateListenable != widget.stateListenable) {
      oldWidget.stateListenable?.removeListener(_onStateChanged);
      widget.stateListenable?.addListener(_onStateChanged);
    }
    if (oldWidget.trackerInfo.id != widget.trackerInfo.id ||
        oldWidget.stateListenable != widget.stateListenable) {
      _trackerInfo = widget.trackerInfo;
      _syncFromListenable(notify: false);
    } else if (widget.stateListenable == null &&
        oldWidget.trackerInfo != widget.trackerInfo) {
      _trackerInfo = widget.trackerInfo;
    }
  }

  @override
  void dispose() {
    widget.stateListenable?.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    _syncFromListenable(notify: true);
  }

  void _syncFromListenable({required bool notify}) {
    final state = widget.stateListenable?.value;
    if (state == null) {
      return;
    }
    TrackerInfo? match;
    for (final item in state.trackerInfos) {
      if (item.id == widget.trackerInfo.id) {
        match = item;
        break;
      }
    }
    final next =
        match ??
        (_trackerInfo.uploadSpeed != null || _trackerInfo.downloadSpeed != null
            ? _trackerInfo.copyWith(uploadSpeed: 0, downloadSpeed: 0)
            : _trackerInfo);
    if (next == _trackerInfo) {
      return;
    }
    if (notify) {
      setState(() {
        _trackerInfo = next;
      });
    } else {
      _trackerInfo = next;
    }
  }

  String _getRuleText() {
    final rule = _trackerInfo.rule;
    final rulePayload = _trackerInfo.rulePayload;
    if (rulePayload.isNotEmpty) {
      return '$rule($rulePayload)';
    }
    return rule;
  }

  String _getProcessText() {
    final process = _trackerInfo.metadata.process;
    final uid = _trackerInfo.metadata.uid;
    if (uid != 0) {
      return '$process($uid)';
    }
    return process;
  }

  String _getEndpointText(String ip, String port) {
    if (ip.isEmpty) {
      return '';
    }
    if (port.isNotEmpty) {
      return '$ip:$port';
    }
    return ip;
  }

  String _formatTrafficValue(int total, int? speed) {
    final totalText = total.traffic.show;
    if (speed == null) {
      return totalText;
    }
    return '${speed.traffic.show}/s ($totalText)';
  }

  Widget _buildChains(BuildContext context) {
    return DecorationListItem(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 20,
        children: [
          Text(context.appLocalizations.proxyChains),
          Flexible(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                for (final chain in _trackerInfo.chains)
                  MetaChip(label: chain),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRows(List<(String, String)> entries) {
    return [
      for (final (title, value) in entries)
        if (value.isNotEmpty) _DetailRow(title: title, value: value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final metadata = _trackerInfo.metadata;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ).copyWith(bottom: 20, top: context.sheetTopPadding),
      children: [
        generateSectionV3(
          title: appLocalizations.basicInfo,
          items: _buildRows([
            (appLocalizations.creationTime, _trackerInfo.start.showFull),
            (appLocalizations.networkType, metadata.network),
            (appLocalizations.process, _getProcessText()),
            (appLocalizations.rule, _getRuleText()),
            (
              appLocalizations.upload,
              _formatTrafficValue(
                _trackerInfo.upload,
                _trackerInfo.uploadSpeed,
              ),
            ),
            (
              appLocalizations.download,
              _formatTrafficValue(
                _trackerInfo.download,
                _trackerInfo.downloadSpeed,
              ),
            ),
          ]),
        ),
        generateSectionV3(
          title: appLocalizations.address,
          items: _buildRows([
            (appLocalizations.host, metadata.host),
            (
              appLocalizations.source,
              _getEndpointText(metadata.sourceIP, metadata.sourcePort),
            ),
            (
              appLocalizations.destination,
              _getEndpointText(
                metadata.destinationIP,
                metadata.destinationPort,
              ),
            ),
            (
              appLocalizations.destinationGeoIP,
              metadata.destinationGeoIP.join(' '),
            ),
            (appLocalizations.destinationIPASN, metadata.destinationIPASN),
            (appLocalizations.remoteDestination, metadata.remoteDestination),
          ]),
        ),
        generateSectionV3(
          title: appLocalizations.proxies,
          items: [
            ..._buildRows([
              (appLocalizations.specialProxy, metadata.specialProxy),
              (appLocalizations.specialRules, metadata.specialRules),
              (appLocalizations.dnsMode, metadata.dnsMode?.name ?? ''),
            ]),
            _buildChains(context),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String title;
  final String value;

  const _DetailRow({required this.title, required this.value});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    context.showNotifier(context.appLocalizations.copySuccess);
  }

  @override
  Widget build(BuildContext context) {
    return DecorationListItem(
      onPressed: () => _copy(context),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 20,
        children: [
          Text(title),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
