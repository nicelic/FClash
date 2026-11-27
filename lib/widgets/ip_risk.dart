import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';

const _riskGradient = [Colors.green, Color(0xFFC57F0A), Colors.red];

extension IpRiskLevelLabelExt on IpRiskLevel {
  String labelOf(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (this) {
      IpRiskLevel.low => l10n.ipRiskLow,
      IpRiskLevel.medium => l10n.ipRiskMedium,
      IpRiskLevel.high => l10n.ipRiskHigh,
      IpRiskLevel.veryHigh => l10n.ipRiskVeryHigh,
    };
  }
}

extension IpRiskGroupLabelExt on IpRiskGroup {
  String labelOf(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (this) {
      IpRiskGroup.datacenter => l10n.ipRiskHostingOrProxy,
      IpRiskGroup.blacklist => l10n.ipRiskBlacklist,
      IpRiskGroup.proxy => l10n.ipRiskProxyType,
    };
  }
}

String _checkLabel(BuildContext context, String name) {
  final l10n = context.appLocalizations;
  return switch (name) {
    'Datacenter' => l10n.ipRiskDatacenter,
    'Anonymizing VPN' => l10n.ipRiskAnonymousVpn,
    'Tor Exit Node' => l10n.ipRiskTorExit,
    'Server' => l10n.ipRiskServer,
    'Public Proxy' => l10n.ipRiskPublicProxy,
    'Web Proxy' => l10n.ipRiskWebProxy,
    'Search Engine Robot' => l10n.ipRiskSearchRobot,
    'Residential Proxy' => l10n.ipRiskResidentialProxy,
    _ => name,
  };
}

Color _scoreColor(int score) {
  final t = (score.clamp(0, 100)) / 100;
  return t < 0.5
      ? Color.lerp(_riskGradient[0], _riskGradient[1], t * 2) ??
            _riskGradient[1]
      : Color.lerp(_riskGradient[1], _riskGradient[2], (t - 0.5) * 2) ??
            _riskGradient[1];
}

Color _tone(BuildContext context, Color color) {
  final hsl = HSLColor.fromColor(color);
  return Theme.of(context).brightness == Brightness.dark
      ? hsl.withLightness(hsl.lightness.clamp(0.66, 1)).toColor()
      : hsl.withLightness(hsl.lightness.clamp(0, 0.38)).toColor();
}

Color _levelColor(IpRiskLevel level) {
  return _scoreColor(switch (level) {
    IpRiskLevel.low => 0,
    IpRiskLevel.medium => 50,
    IpRiskLevel.high || IpRiskLevel.veryHigh => 100,
  });
}

class IpRiskSource extends StatelessWidget {
  const IpRiskSource({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '${context.appLocalizations.ipRiskSource} Scamalytics',
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class IpRiskScoreBar extends StatelessWidget {
  final int score;

  const IpRiskScoreBar({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(colors: _riskGradient);
    final factor = (score.clamp(0, 100)) / 100;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbLeft = math.max(0.0, math.min(width - 14, width * factor - 7));
        return SizedBox(
          height: 14,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Opacity(
                opacity: 0.22,
                child: Container(
                  height: 6,
                  decoration: const ShapeDecoration(
                    gradient: gradient,
                    shape: AppShape.full,
                  ),
                ),
              ),
              ClipRSuperellipse(
                borderRadius: AppRadius.full,
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: factor,
                  child: Container(
                    width: width,
                    height: 6,
                    decoration: const ShapeDecoration(
                      gradient: gradient,
                      shape: AppShape.none,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: thumbLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: ShapeDecoration(
                    shape: AppShape.circle.copyWith(
                      side: BorderSide(color: _scoreColor(score), width: 3),
                    ),
                    color: context.colorScheme.surfaceContainerLowest,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class IpRiskScore extends StatelessWidget {
  final IpRisk risk;

  const IpRiskScore({super.key, required this.risk});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final score = risk.displayScore;
    final color = _scoreColor(score);
    final muted = context.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.ipRiskScore, style: muted),
                    InkResponse(
                      radius: 14,
                      onTap: () => unawaited(showIpRiskNote(context, risk)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.help_outline_rounded,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$score',
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _tone(context, color),
                      ),
                    ),
                    Text(' / 100', style: muted),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: ShapeDecoration(
                color: color.withValues(alpha: 0.14),
                shape: AppShape.sm,
              ),
              child: Text(
                risk.level.labelOf(context),
                style: context.textTheme.labelSmall?.copyWith(
                  color: _tone(context, color),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        IpRiskScoreBar(score: score),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(IpRiskLevel.low.labelOf(context), style: muted),
            Text(IpRiskLevel.high.labelOf(context), style: muted),
          ],
        ),
      ],
    );
  }
}

class IpRiskChecks extends StatelessWidget {
  final IpRisk risk;

  const IpRiskChecks({super.key, required this.risk});

  Widget _chip(BuildContext context, IpRiskCheck check) {
    final colorScheme = context.colorScheme;
    final hit = check.hit;
    final highRisk = risk.displayScore > 10;
    final hitBaseColor = highRisk ? colorScheme.error : _riskGradient[1];
    final color = switch (hit) {
      true => highRisk ? colorScheme.error : _tone(context, hitBaseColor),
      false => colorScheme.onSurfaceVariant,
      null => colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: ShapeDecoration(
        color: hit == true
            ? hitBaseColor.withValues(alpha: highRisk ? 0.12 : 0.14)
            : colorScheme.onSurface.withValues(alpha: 0.05),
        shape: AppShape.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (hit) {
              true => Icons.error_rounded,
              false => Icons.circle_outlined,
              null => Icons.help_outline_rounded,
            },
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            _checkLabel(context, check.name),
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: hit == true ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeChip(BuildContext context) {
    final color = _tone(context, Colors.green);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: ShapeDecoration(
        color: Colors.green.withValues(alpha: 0.14),
        shape: AppShape.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            context.appLocalizations.ipRiskHomeBroadband,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.labelSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final groups = [
      for (final group in IpRiskGroup.values)
        (group, risk.checks.where((check) => check.group == group).toList()),
    ].where((entry) => entry.$2.isNotEmpty).toList();
    final isHome = risk.isHomeBroadband;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, (group, checks)) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          Text(group.labelOf(context), style: muted),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: isHome && group == IpRiskGroup.datacenter
                ? [_homeChip(context)]
                : [for (final check in checks) _chip(context, check)],
          ),
        ],
      ],
    );
  }
}

extension on IpRiskAmount {
  String labelOf(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (this) {
      IpRiskAmount.low => l10n.ipRiskNoteAmountLow,
      IpRiskAmount.medium => l10n.ipRiskNoteAmountMedium,
      IpRiskAmount.high => l10n.ipRiskNoteAmountHigh,
    };
  }
}

extension on IpRiskShare {
  String labelOf(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (this) {
      IpRiskShare.little => l10n.ipRiskNoteShareLittle,
      IpRiskShare.some => l10n.ipRiskNoteShareSome,
      IpRiskShare.almostAll => l10n.ipRiskNoteShareAlmostAll,
    };
  }
}

extension on IpRiskConnection {
  String labelOf(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (this) {
      IpRiskConnection.server => l10n.ipRiskNoteCommercialServer,
      IpRiskConnection.vpn => l10n.ipRiskAnonymousVpn,
      IpRiskConnection.publicProxy => l10n.ipRiskPublicProxy,
      IpRiskConnection.tor => l10n.ipRiskTorExit,
      IpRiskConnection.webProxy => l10n.ipRiskWebProxy,
    };
  }
}

Future<void> showIpRiskNote(BuildContext context, IpRisk risk) async {
  await dialogs.showCommonDialog<void>(
    context: context,
    child: Builder(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return AlertDialog(
          shape: AppShape.xxl,
          title: Text(context.appLocalizations.ipRiskNoteTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.appLocalizations.confirm),
            ),
          ],
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(size.height - 40, 500),
              maxWidth: 320,
            ),
            child: SingleChildScrollView(
              child: IpRiskNoteView(risk: risk.normalized),
            ),
          ),
        );
      },
    ),
  );
}

class IpRiskNoteView extends StatelessWidget {
  final IpRisk risk;

  const IpRiskNoteView({super.key, required this.risk});

  String _basis(BuildContext context) {
    final l10n = context.appLocalizations;
    final note = risk.note;
    final score = risk.displayScore;
    final isp = note?.isp ?? '';
    return switch (note?.direct) {
      true => l10n.ipRiskNoteDirect(score),
      false => l10n.ipRiskNoteIndirect(
        score,
        isp.isNotEmpty ? isp : risk.isp,
      ),
      null => l10n.ipRiskNoteGeneric,
    };
  }

  Widget _row(
    BuildContext context,
    String label,
    InlineSpan value, {
    String? detail,
  }) {
    final muted = context.textTheme.labelSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  value,
                  textAlign: TextAlign.end,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: context.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail, style: muted),
          ],
        ],
      ),
    );
  }

  InlineSpan _party(BuildContext context, String name, IpRiskLevel? level) {
    return TextSpan(
      children: [
        TextSpan(text: name),
        if (level != null) ...[
          const TextSpan(text: ' · '),
          TextSpan(
            text: level.labelOf(context),
            style: TextStyle(color: _tone(context, _levelColor(level))),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final note = risk.note;
    final rows = <Widget>[
      if (note?.amount case final amount?)
        _row(
          context,
          note?.direct == false
              ? l10n.ipRiskNoteAmountIsp
              : l10n.ipRiskNoteAmount,
          TextSpan(text: amount.labelOf(context)),
        ),
      if (note?.share case final share?)
        _row(
          context,
          l10n.ipRiskNoteShare,
          TextSpan(text: share.labelOf(context)),
        ),
      if (note case IpRiskNote(:final operatorName)
          when operatorName.isNotEmpty)
        _row(
          context,
          l10n.isp,
          _party(context, operatorName, note.operatorLevel),
        ),
      if (note case IpRiskNote(:final ownerName)
          when ownerName.isNotEmpty &&
              (ownerName != note.operatorName ||
                  note.ownerLevel != note.operatorLevel))
        _row(
          context,
          l10n.ipRiskNoteOwner,
          _party(context, ownerName, note.ownerLevel),
        ),
      if (note?.connection case final connection?)
        _row(
          context,
          l10n.ipRiskNoteConnection,
          TextSpan(text: connection.labelOf(context)),
          detail: connection == IpRiskConnection.server
              ? null
              : l10n.ipRiskNoteProxying,
        ),
    ];
    final warning = switch (note?.warning) {
      IpRiskLevel.veryHigh => l10n.ipRiskNoteWarningVeryHigh,
      IpRiskLevel.high => l10n.ipRiskNoteWarningHigh,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_basis(context)),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: ShapeDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.05),
              shape: AppShape.lg,
            ),
            child: Column(children: rows),
          ),
        ],
        if (warning != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: ShapeDecoration(
              color: colorScheme.error.withValues(alpha: 0.14),
              shape: AppShape.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: context.textTheme.labelMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          l10n.ipRiskNoteFootnote,
          style: context.textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
