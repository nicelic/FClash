import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IntranetIP extends ConsumerWidget {
  final DashboardTileSize? size;

  const IntranetIP({super.key, this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final localIp = ref.watch(localIpProvider);
    final hasIp = localIp != null && localIp.isNotEmpty;
    final effectiveSize = size ?? DashboardTileSize.small;
    final lines = effectiveSize == DashboardTileSize.tall ? 2 : 1;

    return SizedBox(
      height: getWidgetHeight(lines),
      child: CommonCard(
        radius: AppCorner.lg,
        info: Info(label: appLocalizations.intranetIP, iconData: Icons.devices),
        onPressed: () {
          if (!hasIp) {
            return;
          }
          unawaited(Clipboard.setData(ClipboardData(text: localIp)));
          context.showNotifier(appLocalizations.copySuccess);
        },
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 0),
          child: switch (effectiveSize) {
            DashboardTileSize.tall => Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasIp) ...[
                  MetaChip(label: appLocalizations.privateIp),
                  const SizedBox(height: 8),
                ],
                _buildIpContent(context, localIp),
              ],
            ),
            DashboardTileSize.wide => Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _buildIpContent(context, localIp)),
                    if (hasIp) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.content_copy_rounded,
                        size: 14,
                        color: context.colorScheme.outline,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            DashboardTileSize.small || DashboardTileSize.large => Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [_buildIpContent(context, localIp)],
            ),
          },
        ),
      ),
    );
  }

  Widget _buildIpContent(BuildContext context, String? localIp) {
    final appLocalizations = context.appLocalizations;
    return SizedBox(
      height: globalState.measure.bodyMediumHeight + 2,
      child: FadeThroughBox(
        child: localIp != null
            ? TooltipText(
                text: Text(
                  localIp.isNotEmpty ? localIp : appLocalizations.noNetwork,
                  style: context.textTheme.bodyMedium?.toLight.adjustSize(1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Container(
                padding: const EdgeInsets.all(2),
                child: const AspectRatio(
                  aspectRatio: 1,
                  child: CommonCircleLoading(),
                ),
              ),
      ),
    );
  }
}
