import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  final DashboardTileSize? size;

  const NetworkDetection({super.key, this.size});

  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection>
    with WidgetsBindingObserver {
  Timer? _probeTimer;
  Duration? _scheduledInterval;
  bool _isForeground = true;
  bool _isPageActive = true;
  bool _isWindowVisible = true;
  IpCheckInterval _interval = IpCheckInterval.threeMinutes;
  int _probeGeneration = 0;

  bool get _canProbe =>
      mounted &&
      _isForeground &&
      _isPageActive &&
      _isWindowVisible &&
      _interval.duration != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    ref.listenManual<bool>(windowVisibleProvider, (_, visible) {
      _isWindowVisible = visible;
      _syncProbeTimer();
    }, fireImmediately: true);
    ref.listenManual<IpCheckInterval>(
      appSettingProvider.select((state) => state.ipCheckInterval),
      (_, interval) {
        _interval = interval;
        _syncProbeTimer();
      },
      fireImmediately: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageActivityScope.isActiveOf(context);
    if (_isPageActive == active) {
      return;
    }
    _isPageActive = active;
    _syncProbeTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground == foreground) {
      return;
    }
    _isForeground = foreground;
    _syncProbeTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelProbeTimer();
    super.dispose();
  }

  void _syncProbeTimer() {
    final duration = _interval.duration;
    if (!_canProbe || duration == null) {
      _cancelProbeTimer();
      return;
    }
    if (_probeTimer != null && _scheduledInterval == duration) {
      return;
    }
    _cancelProbeTimer();
    _scheduleNextProbe();
  }

  void _cancelProbeTimer() {
    _probeGeneration++;
    _probeTimer?.cancel();
    _probeTimer = null;
    _scheduledInterval = null;
  }

  void _scheduleNextProbe() {
    final duration = _interval.duration;
    if (duration == null || !_canProbe) {
      return;
    }
    final generation = ++_probeGeneration;
    _scheduledInterval = duration;
    _probeTimer = Timer(duration, () {
      _probeTimer = null;
      if (_canProbe && generation == _probeGeneration) {
        unawaited(_runProbe(generation));
      }
    });
  }

  Future<void> _runProbe(int generation) async {
    try {
      await ref.read(networkDetectionProvider.notifier).probeForDrift();
    } finally {
      if (_canProbe && generation == _probeGeneration) {
        _scheduleNextProbe();
      }
    }
  }

  String _countryText(IpInfo ipInfo) {
    final country = ipInfo.country?.trim() ?? '';
    if (country.isNotEmpty) {
      return country;
    }
    return ipInfo.countryCode;
  }

  String _orgText(IpInfo ipInfo) {
    final asn = ipInfo.asn?.trim() ?? '';
    final asName = ipInfo.asName?.trim() ?? '';
    final isp = ipInfo.isp?.trim() ?? '';
    final label = asName.isNotEmpty ? asName : isp;
    return [
      if (asn.isNotEmpty) asn,
      if (label.isNotEmpty && label != asn) label,
    ].join(' ');
  }

  String _provinceCityText(IpInfo ipInfo) {
    final province = ipInfo.province?.trim() ?? '';
    final city = ipInfo.city?.trim() ?? '';
    return [
      if (province.isNotEmpty) province,
      if (city.isNotEmpty && city != province) city,
    ].join(' · ');
  }

  Widget _buildSettingsButton(BuildContext context) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final isIpMasked = ref.read(
      networkDetectionProvider.select((state) => state.isIpMasked),
    );
    final ipRiskAlert = ref.read(
      appSettingProvider.select((state) => state.ipRiskAlert),
    );
    final ipCheckInterval = ref.read(
      appSettingProvider.select((state) => state.ipCheckInterval),
    );

    return CommonPopupBox(
      targetBuilder: (open) => InkResponse(
        radius: 14,
        onTap: () => open(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.settings_outlined,
            size: 16.ap,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          CommonPopupMenuItem(
            label: l10n.manualRefreshIp,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref.read(networkDetectionProvider.notifier).manualRefresh();
            },
          ),
          CommonPopupMenuItem(
            label: l10n.ipPrivacyProtection,
            icon: isIpMasked
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            selected: isIpMasked,
            onPressed: () {
              ref.read(networkDetectionProvider.notifier).toggleIpPrivacy();
            },
          ),
          CommonPopupMenuItem(
            label: l10n.ipRiskAlert,
            icon: Icons.security_rounded,
            selected: ipRiskAlert,
            onPressed: () {
              ref
                  .read(appSettingProvider.notifier)
                  .update((state) => state.copyWith(ipRiskAlert: !ipRiskAlert));
              ref.read(networkDetectionProvider.notifier).refreshRiskCheck();
            },
          ),
          CommonPopupMenuItem(
            label: l10n.ipCheckInterval,
            icon: Icons.schedule_rounded,
            subItems: [
              for (final item in IpCheckInterval.values)
                CommonPopupMenuItem(
                  label: item.label,
                  selected: item == ipCheckInterval,
                  onPressed: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update((state) => state.copyWith(ipCheckInterval: item));
                  },
                ),
            ],
          ),
          CommonPopupMenuItem(
            label: l10n.tip,
            icon: Icons.info_outline_rounded,
            onPressed: () {
              unawaited(
                dialogs.showMessage(
                  title: l10n.tip,
                  message: TextSpan(text: l10n.detectionTip),
                  cancelable: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    NetworkDetectionState networkDetection,
  ) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final ipInfo = networkDetection.ipInfo;
    final showFlag = ipInfo != null && ipInfo.countryCode.isNotEmpty;
    final riskLevel = networkDetection.riskLevel;
    final hasRisk =
        networkDetection.riskyIp != null &&
        ipInfo != null &&
        !networkDetection.isLoading;
    final riskColor =
        riskLevel == IpRiskLevel.high || riskLevel == IpRiskLevel.veryHigh
        ? colorScheme.error
        : colorScheme.tertiary;

    return Container(
      height: globalState.measure.titleMediumHeight + 16,
      padding: baseInfoEdgeInsets.copyWith(bottom: 0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          showFlag
              ? EmojiText(
                  countryCodeToEmoji(ipInfo.countryCode),
                  style: context.textTheme.titleMedium?.toLight,
                )
              : Icon(Icons.network_check, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: TooltipText(
              text: Text(
                l10n.networkDetection,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildSettingsButton(context),
          if (hasRisk) ...[
            const SizedBox(width: 2),
            InkResponse(
              radius: 14,
              onTap: () {
                final notifier = ref.read(networkDetectionProvider.notifier);
                final preloaded = networkDetection.isIpMasked
                    ? ipInfo
                    : notifier.rawIpInfo;
                unawaited(
                  showIpDetailDialog(
                    context,
                    ipInfo.ip,
                    preloaded: preloaded,
                    showRisk: true,
                    followRiskSetting: false,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 16.ap,
                  color: riskColor,
                ),
              ),
            ),
          ],
          if (networkDetection.isRefreshing && ipInfo != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaField(BuildContext context, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        TooltipText(
          text: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium?.toLight,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusFallback(
    BuildContext context,
    NetworkDetectionState networkDetection,
  ) {
    final l10n = context.appLocalizations;
    return networkDetection.isLoading
        ? Container(
            padding: const EdgeInsets.all(2),
            child: const AspectRatio(
              aspectRatio: 1,
              child: CommonCircleLoading(),
            ),
          )
        : Text(
            networkDetection.errorMessage ?? l10n.timeout,
            style: context.textTheme.bodyMedium
                ?.copyWith(color: context.colorScheme.error)
                .adjustSize(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
  }

  Widget _buildCompactBody(
    BuildContext context,
    NetworkDetectionState networkDetection, {
    required bool wide,
  }) {
    final ipInfo = networkDetection.ipInfo;
    final ipStyle = context.textTheme.bodyMedium?.toLight.adjustSize(1);
    final metaParts = ipInfo == null
        ? const <String>[]
        : [
            if (_countryText(ipInfo).isNotEmpty) _countryText(ipInfo),
            if (_orgText(ipInfo).isNotEmpty) _orgText(ipInfo),
          ];

    return Container(
      padding: baseInfoEdgeInsets.copyWith(top: 0),
      child: SizedBox(
        height: globalState.measure.bodyMediumHeight + 2,
        child: FadeThroughBox(
          child: ipInfo != null
              ? wide
                    ? Row(
                        children: [
                          TooltipText(
                            text: Text(
                              ipInfo.ip,
                              style: ipStyle?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TooltipText(
                                text: Text(
                                  metaParts.join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : TooltipText(
                        text: Text(
                          ipInfo.ip,
                          style: ipStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
              : _buildStatusFallback(context, networkDetection),
        ),
      ),
    );
  }

  Widget _buildTallBody(
    BuildContext context,
    NetworkDetectionState networkDetection,
  ) {
    final l10n = context.appLocalizations;
    final ipInfo = networkDetection.ipInfo;
    if (ipInfo == null) {
      return Container(
        padding: baseInfoEdgeInsets.copyWith(top: 0),
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          height: globalState.measure.bodyMediumHeight + 2,
          child: FadeThroughBox(
            child: _buildStatusFallback(context, networkDetection),
          ),
        ),
      );
    }
    final country = _countryText(ipInfo);
    final org = _orgText(ipInfo);
    return Padding(
      padding: baseInfoEdgeInsets.copyWith(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TooltipText(
            text: Text(
              ipInfo.ip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (country.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildMetaField(context, l10n.countryOrRegion, country),
          ],
          if (org.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildMetaField(context, l10n.operatorOrAsn, org),
          ],
        ],
      ),
    );
  }

  Widget _buildLargeBody(
    BuildContext context,
    NetworkDetectionState networkDetection,
  ) {
    final l10n = context.appLocalizations;
    final ipInfo = networkDetection.ipInfo;
    if (ipInfo == null) {
      return Container(
        padding: baseInfoEdgeInsets.copyWith(top: 0),
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          height: globalState.measure.bodyMediumHeight + 2,
          child: FadeThroughBox(
            child: _buildStatusFallback(context, networkDetection),
          ),
        ),
      );
    }
    final country = _countryText(ipInfo);
    final region = _provinceCityText(ipInfo);
    final org = _orgText(ipInfo);
    final isp = ipInfo.isp?.trim() ?? '';
    final domain = ipInfo.asDomain?.trim() ?? '';
    final rightBottomLabel = isp.isNotEmpty
        ? l10n.isp
        : domain.isNotEmpty
        ? l10n.organizationDomain
        : '';
    final rightBottomValue = isp.isNotEmpty ? isp : domain;

    return Padding(
      padding: baseInfoEdgeInsets.copyWith(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TooltipText(
            text: Text(
              ipInfo.ip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (country.isNotEmpty || org.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (country.isNotEmpty)
                        _buildMetaField(context, l10n.countryOrRegion, country),
                      if (country.isNotEmpty && org.isNotEmpty)
                        const SizedBox(height: 6),
                      if (org.isNotEmpty)
                        _buildMetaField(context, l10n.operatorOrAsn, org),
                    ],
                  ),
                ),
              if ((country.isNotEmpty || org.isNotEmpty) &&
                  (region.isNotEmpty || rightBottomValue.isNotEmpty))
                const SizedBox(width: 12),
              if (region.isNotEmpty || rightBottomValue.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (region.isNotEmpty)
                        _buildMetaField(context, l10n.provinceAndCity, region),
                      if (region.isNotEmpty && rightBottomValue.isNotEmpty)
                        const SizedBox(height: 6),
                      if (rightBottomValue.isNotEmpty)
                        _buildMetaField(
                          context,
                          rightBottomLabel,
                          rightBottomValue,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleCardTap(NetworkDetectionState networkDetection) {
    final ipInfo = networkDetection.ipInfo;
    if (ipInfo == null) {
      if (!networkDetection.isLoading) {
        ref.read(networkDetectionProvider.notifier).manualRefresh();
      }
      return;
    }
    final notifier = ref.read(networkDetectionProvider.notifier);
    final preloaded = networkDetection.isIpMasked ? ipInfo : notifier.rawIpInfo;
    unawaited(
      showIpDetailDialog(context, ipInfo.ip, preloaded: preloaded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final networkDetection = ref.watch(networkDetectionProvider);
    final effectiveSize = widget.size ?? DashboardTileSize.small;
    final isTallHeight =
        effectiveSize == DashboardTileSize.tall ||
        effectiveSize == DashboardTileSize.large;

    return SizedBox(
      height: getWidgetHeight(isTallHeight ? 2 : 1),
      child: CommonCard(
        radius: AppCorner.lg,
        onPressed: () => _handleCardTap(networkDetection),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, networkDetection),
            switch (effectiveSize) {
              DashboardTileSize.small => _buildCompactBody(
                context,
                networkDetection,
                wide: false,
              ),
              DashboardTileSize.wide => _buildCompactBody(
                context,
                networkDetection,
                wide: true,
              ),
              DashboardTileSize.tall => Expanded(
                child: _buildTallBody(context, networkDetection),
              ),
              DashboardTileSize.large => Expanded(
                child: _buildLargeBody(context, networkDetection),
              ),
            },
          ],
        ),
      ),
    );
  }
}
