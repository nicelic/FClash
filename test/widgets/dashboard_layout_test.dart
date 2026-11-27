import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/widgets/grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('dashboard uses 12 columns from 480 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(511, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    final grid = find.byType(Grid);
    expect(tester.getSize(grid).width, 479);
    expect(tester.widget<Grid>(grid).crossAxisCount, 8);

    tester.view.physicalSize = const Size(512, 1000);
    await tester.pump();

    expect(tester.getSize(grid).width, 480);
    expect(tester.widget<Grid>(grid).crossAxisCount, 12);
    expect(tester.takeException(), null);
  });

  testWidgets('dashboard limits a wide grid to 16 centered columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    final grid = find.byType(Grid);
    expect(tester.widget<Grid>(grid).crossAxisCount, 16);
    expect(tester.getSize(grid).width, 1120);
    expect(tester.getTopLeft(grid).dx, 240);
    expect(tester.takeException(), null);
  });

  testWidgets('dashboard cycles card sizes and persists sizes and variants', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingProvider.notifier).update(
          (state) => state.copyWith(
            dashboardWidgets: [
              DashboardWidget.networkDetection,
              DashboardWidget.outboundMode,
            ],
            dashboardWidgetSizes: const {},
          ),
        );
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('edit-icon')));
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> tapFirstResize() async {
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.open_in_full_rounded).first,
          matching: find.byType(IconButton),
        ),
      );
      button.onPressed!();
      await tester.pump();
    }

    await tapFirstResize();
    expect(
      container.read(appSettingProvider).dashboardWidgetSizes['networkDetection'],
      DashboardTileSize.wide,
    );
    await tapFirstResize();
    expect(
      container.read(appSettingProvider).dashboardWidgetSizes['networkDetection'],
      DashboardTileSize.tall,
    );
    await tapFirstResize();
    expect(
      container.read(appSettingProvider).dashboardWidgetSizes['networkDetection'],
      DashboardTileSize.large,
    );
    await tapFirstResize();
    expect(
      container.read(appSettingProvider).dashboardWidgetSizes['networkDetection'],
      DashboardTileSize.small,
    );

    final secondResize = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.open_in_full_rounded).at(1),
        matching: find.byType(IconButton),
      ),
    );
    secondResize.onPressed!();
    await tester.pump();

    expect(
      container.read(appSettingProvider).dashboardWidgets,
      [DashboardWidget.networkDetection, DashboardWidget.outboundModeV2],
    );
    expect(tester.takeException(), null);
  });
}
