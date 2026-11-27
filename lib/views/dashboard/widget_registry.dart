import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:fl_clash/widgets/widgets.dart';

extension DashboardWidgetView on DashboardWidget {
  GridItem get widget => switch (this) {
    DashboardWidget.networkSpeed => const GridItem(
      crossAxisCellCount: 8,
      child: NetworkSpeed(),
    ),
    DashboardWidget.outboundModeV2 => const GridItem(
      crossAxisCellCount: 8,
      child: OutboundModeV2(),
    ),
    DashboardWidget.outboundMode => const GridItem(
      crossAxisCellCount: 4,
      child: OutboundMode(),
    ),
    DashboardWidget.trafficUsage => const GridItem(
      crossAxisCellCount: 4,
      child: TrafficUsage(),
    ),
    DashboardWidget.networkDetection => const GridItem(
      crossAxisCellCount: 4,
      child: NetworkDetection(),
    ),
    DashboardWidget.tunButton => const GridItem(
      crossAxisCellCount: 4,
      child: TUNButton(),
    ),
    DashboardWidget.vpnButton => const GridItem(
      crossAxisCellCount: 4,
      child: VpnButton(),
    ),
    DashboardWidget.systemProxyButton => const GridItem(
      crossAxisCellCount: 4,
      child: SystemProxyButton(),
    ),
    DashboardWidget.intranetIp => const GridItem(
      crossAxisCellCount: 4,
      child: IntranetIP(),
    ),
    DashboardWidget.memoryInfo => const GridItem(
      crossAxisCellCount: 4,
      child: MemoryInfo(),
    ),
  };
}

DashboardTileSize resolveDashboardSize(
  DashboardWidget item,
  Map<String, DashboardTileSize> sizes,
) {
  final saved = sizes[item.family.name] ?? item.nativeSize;
  return item.sizes.contains(saved) ? saved : item.nativeSize;
}

GridItem buildDashboardTile(DashboardWidget item, DashboardTileSize size) {
  final effectiveSize = item.sizes.contains(size) ? size : item.nativeSize;
  return switch ((item.family, effectiveSize)) {
    (DashboardWidget.networkSpeed, DashboardTileSize.small) => const GridItem(
      crossAxisCellCount: 4,
      child: NetworkSpeed(size: DashboardTileSize.small),
    ),
    (DashboardWidget.networkSpeed, DashboardTileSize.wide) => const GridItem(
      crossAxisCellCount: 8,
      child: NetworkSpeed(size: DashboardTileSize.wide),
    ),
    (DashboardWidget.networkSpeed, DashboardTileSize.tall) => const GridItem(
      crossAxisCellCount: 4,
      child: NetworkSpeed(size: DashboardTileSize.tall),
    ),
    (DashboardWidget.networkSpeed, DashboardTileSize.large) =>
      DashboardWidget.networkSpeed.widget,
    (DashboardWidget.outboundModeV2, DashboardTileSize.tall) =>
      DashboardWidget.outboundMode.widget,
    (DashboardWidget.outboundModeV2, DashboardTileSize.wide) =>
      DashboardWidget.outboundModeV2.widget,
    (DashboardWidget.trafficUsage, DashboardTileSize.wide) => const GridItem(
      crossAxisCellCount: 8,
      child: TrafficUsage(size: DashboardTileSize.wide),
    ),
    (DashboardWidget.trafficUsage, DashboardTileSize.tall) =>
      DashboardWidget.trafficUsage.widget,
    (DashboardWidget.networkDetection, DashboardTileSize.small) =>
      DashboardWidget.networkDetection.widget,
    (DashboardWidget.networkDetection, DashboardTileSize.wide) =>
      const GridItem(
        crossAxisCellCount: 8,
        child: NetworkDetection(size: DashboardTileSize.wide),
      ),
    (DashboardWidget.networkDetection, DashboardTileSize.tall) =>
      const GridItem(
        crossAxisCellCount: 4,
        child: NetworkDetection(size: DashboardTileSize.tall),
      ),
    (DashboardWidget.networkDetection, DashboardTileSize.large) =>
      const GridItem(
        crossAxisCellCount: 8,
        child: NetworkDetection(size: DashboardTileSize.large),
      ),
    (DashboardWidget.intranetIp, DashboardTileSize.small) =>
      DashboardWidget.intranetIp.widget,
    (DashboardWidget.intranetIp, DashboardTileSize.wide) => const GridItem(
      crossAxisCellCount: 8,
      child: IntranetIP(size: DashboardTileSize.wide),
    ),
    (DashboardWidget.intranetIp, DashboardTileSize.tall) => const GridItem(
      crossAxisCellCount: 4,
      child: IntranetIP(size: DashboardTileSize.tall),
    ),
    (DashboardWidget.memoryInfo, DashboardTileSize.small) =>
      DashboardWidget.memoryInfo.widget,
    (DashboardWidget.memoryInfo, DashboardTileSize.wide) => const GridItem(
      crossAxisCellCount: 8,
      child: MemoryInfo(size: DashboardTileSize.wide),
    ),
    (DashboardWidget.memoryInfo, DashboardTileSize.tall) => const GridItem(
      crossAxisCellCount: 4,
      child: MemoryInfo(size: DashboardTileSize.tall),
    ),
    _ => item.widget,
  };
}

DashboardWidget dashboardWidgetOf(GridItem gridItem) {
  return DashboardWidget.values.firstWhere(
    (item) => item.widget == gridItem,
    orElse: () => switch (gridItem.child) {
      NetworkSpeed() => DashboardWidget.networkSpeed,
      OutboundModeV2() => DashboardWidget.outboundModeV2,
      OutboundMode() => DashboardWidget.outboundMode,
      TrafficUsage() => DashboardWidget.trafficUsage,
      NetworkDetection() => DashboardWidget.networkDetection,
      TUNButton() => DashboardWidget.tunButton,
      VpnButton() => DashboardWidget.vpnButton,
      SystemProxyButton() => DashboardWidget.systemProxyButton,
      IntranetIP() => DashboardWidget.intranetIp,
      MemoryInfo() => DashboardWidget.memoryInfo,
      _ => throw StateError('Unknown GridItem child: ${gridItem.child}'),
    },
  );
}
