import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSpeed extends StatefulWidget {
  final DashboardTileSize? size;

  const NetworkSpeed({super.key, this.size});

  @override
  State<NetworkSpeed> createState() => _NetworkSpeedState();
}

class _NetworkSpeedState extends State<NetworkSpeed> {
  static const _initPoints = [Point(0, 0), Point(1, 0)];

  List<Point> _getPoints(List<Traffic> traffics) {
    final trafficPoints = [
      for (final (index, item) in traffics.indexed)
        Point((index + _initPoints.length).toDouble(), item.speed.toDouble()),
    ];
    return [..._initPoints, ...trafficPoints];
  }

  Traffic _getLastTraffic(List<Traffic> traffics) {
    if (traffics.isEmpty) return const Traffic();
    return traffics.last;
  }

  Widget _buildHeader(
    BuildContext context, {
    required String label,
    String? trailing,
    EdgeInsets? padding,
  }) {
    final color = context.colorScheme.onSurfaceVariant.opacity80;
    return Padding(
      padding: padding ?? baseInfoEdgeInsets.copyWith(bottom: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: InfoHeader(
              padding: EdgeInsets.zero,
              info: Info(label: label, iconData: Icons.speed_sharp),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing,
              style: context.textTheme.bodySmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<Traffic> traffics) {
    return LineChart(
      gradient: true,
      color: context.colorScheme.primary,
      points: _getPoints(traffics),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final effectiveSize = widget.size ?? DashboardTileSize.large;
    final lines =
        effectiveSize == DashboardTileSize.small ||
            effectiveSize == DashboardTileSize.wide
        ? 1
        : 2;

    return SizedBox(
      height: getWidgetHeight(lines),
      child: RepaintBoundary(
        child: CommonCard(
          radius: AppCorner.lg,
          onPressed: () {},
          child: Consumer(
            builder: (_, ref, _) {
              final traffics = ref.watch(trafficsProvider).list;
              final lastTraffic = _getLastTraffic(traffics);
              return switch (effectiveSize) {
                DashboardTileSize.small => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, label: appLocalizations.networkSpeed),
                    Expanded(
                      child: Padding(
                        padding: baseInfoEdgeInsets.copyWith(top: 0),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '↑ ${lastTraffic.up.traffic.show}/s',
                                  style: context.textTheme.labelMedium?.toLight,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '↓ ${lastTraffic.down.traffic.show}/s',
                                  style: context.textTheme.labelMedium?.toLight,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                DashboardTileSize.wide => Column(
                  children: [
                    _buildHeader(
                      context,
                      label: appLocalizations.networkSpeed,
                      trailing: lastTraffic.speedText,
                      padding: EdgeInsets.fromLTRB(16.mAp, 10.mAp, 16.mAp, 0),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildChart(context, traffics),
                      ),
                    ),
                  ],
                ),
                DashboardTileSize.tall => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, label: appLocalizations.networkSpeed),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.mAp, 6, 16.mAp, 0),
                      child: TooltipText(
                        text: Text(
                          lastTraffic.speedText,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant.opacity80,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildChart(context, traffics),
                      ),
                    ),
                  ],
                ),
                DashboardTileSize.large => Column(
                  children: [
                    _buildHeader(
                      context,
                      label: appLocalizations.networkSpeed,
                      trailing: lastTraffic.speedText,
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _buildChart(context, traffics),
                      ),
                    ),
                  ],
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}
