import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/widgets/ip_risk.dart';
import 'package:fl_clash/widgets/loading.dart';
import 'package:fl_clash/widgets/text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _stripIpPort(String rawIp) {
  final cleanIp = rawIp.trim();
  if (cleanIp.startsWith('[') && cleanIp.contains(']')) {
    return cleanIp.substring(1, cleanIp.indexOf(']'));
  }
  if (cleanIp.contains(':') && !cleanIp.contains('::')) {
    final parts = cleanIp.split(':');
    if (parts.length == 2 && int.tryParse(parts[1]) != null) {
      return parts[0];
    }
  }
  return cleanIp;
}

Future<void> showIpDetailDialog(
  BuildContext context,
  String rawIp, {
  IpInfo? preloaded,
  bool showRisk = false,
  bool followRiskSetting = true,
}) async {
  final cleanIp = _stripIpPort(rawIp);
  if (cleanIp.isEmpty) {
    return;
  }

  final isPublic = classifyIp(cleanIp) == IpCategory.public;
  final savedDetail = followRiskSetting
      ? ProviderScope.containerOf(
          context,
          listen: false,
        ).read(appSettingProvider).ipRiskDetail
      : false;
  final riskView = (showRisk || savedDetail) && isPublic;

  final preloadedRisk = riskView
      ? await ipIntelCache
            .readRisk(cleanIp)
            .timeout(const Duration(milliseconds: 300), onTimeout: () => null)
      : null;

  final info =
      preloaded ??
      (isPublic && !riskView
          ? await ipIntelCache
                .readDetail(cleanIp)
                .timeout(
                  const Duration(milliseconds: 300),
                  onTimeout: () => null,
                )
          : null);

  if (!context.mounted) {
    return;
  }

  await dialogs.showCommonDialog<void>(
    context: context,
    child: _IpDetailDialog(
      ip: cleanIp,
      preloaded: info,
      riskView: riskView,
      preloadedRisk: preloadedRisk,
      persistRisk: followRiskSetting,
    ),
  );
}

class _IpDetailDialog extends ConsumerStatefulWidget {
  final String ip;
  final IpInfo? preloaded;
  final bool riskView;
  final IpRisk? preloadedRisk;
  final bool persistRisk;

  const _IpDetailDialog({
    required this.ip,
    this.preloaded,
    this.riskView = false,
    this.preloadedRisk,
    this.persistRisk = true,
  });

  @override
  ConsumerState<_IpDetailDialog> createState() => _IpDetailDialogState();
}

class _IpDetailDialogState extends ConsumerState<_IpDetailDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  IpCategory? _category;
  IpInfo? _ipInfo;
  String? _riskIp;
  IpRisk? _risk;
  bool _riskFailed = false;
  bool _editing = false;
  int _riskSerial = 0;
  final _cancelToken = CancelToken();
  final _ipController = TextEditingController();

  @override
  void dispose() {
    _cancelToken.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.riskView) {
      _riskIp = widget.ip;
      if (widget.preloadedRisk case final risk?) {
        _risk = risk;
      } else {
        unawaited(_fetchRisk(widget.ip));
      }
    }
    final preloaded = widget.preloaded;
    if (preloaded != null && preloaded.hasDetails) {
      _ipInfo = preloaded;
      _isLoading = false;
      return;
    }
    unawaited(_fetchIpDetail());
  }

  Future<void> _afterEntrance() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status != AnimationStatus.forward) {
      return;
    }
    final completer = Completer<void>();
    void listener(AnimationStatus status) {
      if (status != AnimationStatus.forward && !completer.isCompleted) {
        completer.complete();
      }
    }

    animation.addStatusListener(listener);
    await completer.future;
    animation.removeStatusListener(listener);
  }

  Future<void> _fetchIpDetail() async {
    final l10n = context.appLocalizations;
    final cat = classifyIp(widget.ip);
    if (cat != IpCategory.public) {
      if (mounted) {
        setState(() {
          _category = cat;
          _isLoading = false;
        });
      }
      return;
    }

    final res = await request.queryIpDetail(
      widget.ip,
      cancelToken: _cancelToken,
    );
    if (!mounted) return;
    await _afterEntrance();
    if (!mounted) return;

    if (res.isError || res.data == null) {
      if (widget.preloaded != null) {
        setState(() {
          _ipInfo = widget.preloaded;
          _errorMessage = null;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = l10n.networkErrorRetryLater;
          _isLoading = false;
        });
      }
    } else {
      final fetched = res.data!;
      final merged = widget.preloaded != null
          ? widget.preloaded!.merge(fetched)
          : fetched;
      setState(() {
        _ipInfo = merged;
        _errorMessage = null;
        _isLoading = false;
      });
    }
  }

  ShapeDecoration _tileDecoration(BuildContext context) {
    return ShapeDecoration(
      color: context.colorScheme.surfaceContainerHigh,
      shape: AppShape.md,
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color iconColor,
    String label = '',
    required String value,
    Widget? action,
    Widget? customValue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _tileDecoration(context),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: ShapeDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: AppShape.circle,
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: label.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      customValue ??
                          SelectableText(
                            value,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                          ),
                    ],
                  )
                : (customValue ??
                      SelectableText(
                        value,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      )),
          ),
          if (action != null) ...[const SizedBox(width: 4), action],
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(icon, size: 16, color: context.colorScheme.onSurfaceVariant),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  void _loadRisk(String ip, {bool force = false}) {
    setState(() {
      _riskIp = ip;
      _risk = null;
      _riskFailed = false;
      _editing = false;
    });
    unawaited(_fetchRisk(ip, force: force));
  }

  Future<void> _fetchRisk(String ip, {bool force = false}) async {
    final serial = ++_riskSerial;
    final res = await request.queryIpRisk(
      ip,
      force: force,
      cancelToken: _cancelToken,
    );
    if (!mounted) return;
    await _afterEntrance();
    if (!mounted || serial != _riskSerial) return;
    setState(() {
      _risk = res.data;
      _riskFailed = res.isError || res.data == null;
    });
  }

  void _submitIp(String value) {
    final l10n = context.appLocalizations;
    final address = InternetAddress.tryParse(value.trim());
    if (address == null || classifyIp(address.address) != IpCategory.public) {
      context.showNotifier(l10n.ipRiskInvalid);
      return;
    }
    if (address.address == _riskIp && _risk != null) {
      setState(() => _editing = false);
      return;
    }
    _loadRisk(address.address);
  }

  void _toggleRisk() {
    final detail = _riskIp == null;
    if (widget.persistRisk) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(ipRiskDetail: detail));
    }
    if (detail) {
      _loadRisk(widget.ip);
      return;
    }
    setState(() {
      _riskSerial++;
      _riskIp = null;
      _risk = null;
      _riskFailed = false;
      _editing = false;
    });
  }

  Widget _buildRiskButton() {
    return _buildIconButton(
      icon: Icons.swap_horiz_rounded,
      tooltip: context.appLocalizations.toggle,
      onPressed: _toggleRisk,
    );
  }

  Widget _buildRiskCard(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: _tileDecoration(context),
      child: child,
    );
  }

  Widget _buildRiskIpTile(String ip) {
    final l10n = context.appLocalizations;
    final valueStyle = context.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return _buildStatTile(
      icon: Icons.location_on_rounded,
      iconColor: context.colorScheme.primary,
      label: l10n.ipAddress,
      value: ip,
      customValue: _editing
          ? TextField(
              controller: _ipController,
              autofocus: true,
              style: valueStyle,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.ipRiskHint,
                hintStyle: valueStyle?.copyWith(
                  fontWeight: FontWeight.normal,
                  color: context.colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: _submitIp,
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _ipController.text = ip;
                setState(() => _editing = true);
              },
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      ip,
                      style: valueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
      action: _editing
          ? _buildIconButton(
              icon: Icons.search_rounded,
              tooltip: l10n.search,
              onPressed: () => _submitIp(_ipController.text),
            )
          : _buildRiskButton(),
    );
  }

  Widget _buildRiskInfo(IpRisk risk) {
    final l10n = context.appLocalizations;
    final muted = context.textTheme.labelSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final valueStyle = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    Widget? cell(String label, String value, {Widget? leading}) {
      if (value.isEmpty) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          const SizedBox(height: 1),
          Row(
            children: [
              ?leading,
              Flexible(child: SelectableText(value, style: valueStyle)),
            ],
          ),
        ],
      );
    }

    final countryCode = IpInfo.normalizeCountryCode(
      risk.countryCode,
      risk.country,
      risk.region,
    );
    final countryName =
        IpInfo.normalizeCountry(risk.country, countryCode, risk.region) ?? '';
    final country = cell(
      l10n.countryOrRegion,
      countryName.isNotEmpty ? countryName : countryCode,
      leading: countryCode.length == 2
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: EmojiText(
                countryCodeToEmoji(countryCode),
                style: const TextStyle(fontSize: 14),
              ),
            )
          : null,
    );
    final region = cell(
      l10n.provinceAndCity,
      [
        if (risk.region.isNotEmpty) risk.region,
        if (risk.city.isNotEmpty && risk.city != risk.region) risk.city,
      ].join(' · '),
    );
    final rows = <Widget>[
      if (country != null && region != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: country),
            const SizedBox(width: 12),
            Expanded(child: region),
          ],
        )
      else
        ?(country ?? region),
      ?cell(
        l10n.operatorOrAsn,
        [
          if (risk.organization.isNotEmpty) risk.organization,
          if (risk.asn.isNotEmpty) risk.asn,
        ].join(' · '),
      ),
      if (risk.isp != risk.organization) ?cell(l10n.isp, risk.isp),
      ?cell(l10n.ipRiskHostname, risk.hostname),
    ];
    return _buildRiskCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _fadeSwitcher(Widget child) {
    return AnimatedSwitcher(
      duration: context.motionDuration(const Duration(milliseconds: 300)),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0.4, 1, curve: Curves.easeOut),
        ),
        child: child,
      ),
      layoutBuilder: (current, previous) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topLeft,
        children: [
          for (final child in previous)
            Positioned(left: 0, top: 0, right: 0, child: child),
          ?current,
        ],
      ),
      child: child,
    );
  }

  Widget _spaced(List<Widget> items, {Key? key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          items[i],
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildRiskContent(String ip) {
    final l10n = context.appLocalizations;
    final risk = _risk;
    final body = risk != null
        ? _spaced(key: ValueKey(risk), [
            _buildRiskCard(IpRiskScore(risk: risk)),
            if (risk.checks.isNotEmpty)
              _buildRiskCard(IpRiskChecks(risk: risk)),
            _buildRiskInfo(risk),
            const IpRiskSource(),
          ])
        : KeyedSubtree(
            key: ValueKey(_riskFailed),
            child: _buildRiskCard(
              SizedBox(
                height: 84,
                child: _riskFailed
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.networkErrorRetryLater,
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.error,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _loadRisk(ip, force: true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(l10n.retry),
                          ),
                        ],
                      )
                    : const Center(
                        child: CommonCircleLoading(
                          constraints: BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                        ),
                      ),
              ),
            ),
          );
    return _spaced(key: const ValueKey('risk'), [
      _buildRiskIpTile(ip),
      _fadeSwitcher(body),
    ]);
  }

  Widget _buildDetailContent(BuildContext context) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    if (_isLoading) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CommonCircleLoading(
            constraints: BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ),
      );
    }
    if (_category == IpCategory.tun) {
      return _spaced([
        _buildStatTile(
          icon: Icons.location_on_rounded,
          iconColor: colorScheme.primary,
          label: l10n.ipAddress,
          value: widget.ip,
        ),
        _buildStatTile(
          icon: Icons.stacked_line_chart,
          iconColor: colorScheme.tertiary,
          label: l10n.tunVirtualAddress,
          value: 'TUN Virtual Network Adapter',
        ),
      ]);
    }
    if (_category == IpCategory.lan) {
      return _spaced([
        _buildStatTile(
          icon: Icons.location_on_rounded,
          iconColor: colorScheme.primary,
          label: l10n.ipAddress,
          value: widget.ip,
        ),
        _buildStatTile(
          icon: Icons.shuffle_rounded,
          iconColor: colorScheme.secondary,
          label: l10n.privateIp,
          value: 'LAN / Private Network',
        ),
      ]);
    }
    if (_errorMessage != null) {
      return _spaced([
        _buildStatTile(
          icon: Icons.location_on_rounded,
          iconColor: colorScheme.primary,
          label: l10n.ipAddress,
          value: widget.ip,
          action: _buildRiskButton(),
        ),
        _buildStatTile(
          icon: Icons.error_outline,
          iconColor: colorScheme.error,
          value: _errorMessage!,
          customValue: Text(
            _errorMessage!,
            style: context.textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
          ),
          action: _buildIconButton(
            icon: Icons.refresh_rounded,
            tooltip: l10n.retry,
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              unawaited(_fetchIpDetail());
            },
          ),
        ),
      ]);
    }

    final ipInfo = _ipInfo;
    final flagEmoji = (ipInfo != null && ipInfo.countryCode.isNotEmpty)
        ? countryCodeToEmoji(ipInfo.countryCode)
        : '';
    final countryText = ipInfo != null
        ? [
            if (ipInfo.country != null && ipInfo.country!.isNotEmpty)
              ipInfo.country,
            if (ipInfo.countryCode.isNotEmpty) ipInfo.countryCode,
          ].join(' · ')
        : '';
    final provinceCity = ipInfo != null
        ? [
            if (ipInfo.province != null && ipInfo.province!.isNotEmpty)
              ipInfo.province,
            if (ipInfo.city != null &&
                ipInfo.city!.isNotEmpty &&
                ipInfo.city != ipInfo.province)
              ipInfo.city,
          ].join(' · ')
        : '';
    final ispText = (ipInfo?.isp != null && ipInfo!.isp!.isNotEmpty)
        ? ipInfo.isp!
        : '';
    final operatorText = ipInfo != null
        ? [
            if (ipInfo.asName != null &&
                ipInfo.asName!.isNotEmpty &&
                ipInfo.asName != ipInfo.isp &&
                ipInfo.asName != ipInfo.asDomain)
              ipInfo.asName,
            if (ipInfo.asn != null && ipInfo.asn!.isNotEmpty) ipInfo.asn,
          ].join(' · ')
        : '';
    final domainText =
        (ipInfo?.asDomain != null && ipInfo!.asDomain!.isNotEmpty)
        ? ipInfo.asDomain!
        : '';

    return _spaced([
      _buildStatTile(
        icon: Icons.location_on_rounded,
        iconColor: colorScheme.primary,
        label: l10n.ipAddress,
        value: widget.ip,
        action: _buildRiskButton(),
      ),
      if (countryText.isNotEmpty || flagEmoji.isNotEmpty)
        _buildStatTile(
          icon: Icons.flag_rounded,
          iconColor: colorScheme.secondary,
          label: l10n.countryOrRegion,
          value: countryText,
          customValue: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (flagEmoji.isNotEmpty) ...[
                EmojiText(flagEmoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: SelectableText(
                  countryText,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      if (provinceCity.isNotEmpty)
        _buildStatTile(
          icon: Icons.location_city_rounded,
          iconColor: colorScheme.tertiary,
          label: l10n.provinceAndCity,
          value: provinceCity,
        ),
      if (operatorText.isNotEmpty)
        _buildStatTile(
          icon: Icons.business_rounded,
          iconColor: colorScheme.secondary,
          label: l10n.operatorOrAsn,
          value: operatorText,
        ),
      if (ispText.isNotEmpty)
        _buildStatTile(
          icon: Icons.router_rounded,
          iconColor: colorScheme.primary,
          label: l10n.isp,
          value: ispText,
        ),
      if (domainText.isNotEmpty)
        _buildStatTile(
          icon: Icons.link_rounded,
          iconColor: colorScheme.tertiary,
          label: l10n.organizationDomain,
          value: domainText,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final size = MediaQuery.sizeOf(context);
    final content = _riskIp != null
        ? _buildRiskContent(_riskIp!)
        : _buildDetailContent(context);

    return AlertDialog(
      shape: AppShape.xxl,
      backgroundColor: context.colorScheme.surfaceContainerLow,
      title: Text(l10n.moreIpInfo),
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirm),
        ),
      ],
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(size.height - 40, 520),
          maxWidth: 340,
        ),
        child: SizedBox(
          width: math.max(0, math.min(340, size.width - 64)),
          child: SingleChildScrollView(
            child: AnimatedSize(
              duration: context.motionDuration(
                const Duration(milliseconds: 300),
              ),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _fadeSwitcher(content),
            ),
          ),
        ),
      ),
    );
  }
}
