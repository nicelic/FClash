import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:fl_clash/widgets/null_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

TrackerInfo _tracker({
  required String id,
  String host = 'example.com',
  String process = 'curl',
  List<String> chains = const ['Proxy'],
  int upload = 0,
  int download = 0,
  DateTime? start,
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    start: start ?? DateTime.utc(2026),
    metadata: Metadata(
      network: 'tcp',
      host: host,
      destinationIP: '1.1.1.1',
      destinationPort: '443',
      process: process,
    ),
    chains: chains,
    rule: 'DOMAIN',
    rulePayload: host,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;
  late ProviderContainer container;

  setUpAll(() {
    core = MockCoreHandlerInterface();
    CoreController.resetInstance();
    CoreController.test(core);
  });

  tearDownAll(CoreController.resetInstance);

  setUp(() {
    reset(core);
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpConnections(
    WidgetTester tester, {
    int Function()? speedNowMs,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: ConnectionsView(speedNowMs: speedNowMs)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> teardownView(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('shows the empty state when core reports no connections', (
    tester,
  ) async {
    when(core.getConnections).thenAnswer((_) async => const <TrackerInfo>[]);

    await pumpConnections(tester);

    expect(find.byType(NullStatus), findsOneWidget);
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets('renders one row per reported connection', (tester) async {
    when(core.getConnections).thenAnswer(
      (_) async => [
        _tracker(id: 'a', host: 'alpha.test'),
        _tracker(id: 'b', host: 'beta.test'),
      ],
    );

    await pumpConnections(tester);
    await tester.pump(commonDuration);
    await tester.pump(commonDuration);

    expect(find.byType(NullStatus), findsNothing);
    expect(find.textContaining('alpha.test'), findsWidgets);
    expect(find.textContaining('beta.test'), findsWidgets);
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets('orders rows by creation time newest first by default', (
    tester,
  ) async {
    when(core.getConnections).thenAnswer(
      (_) async => [
        _tracker(
          id: 'a',
          host: 'alpha.test',
          download: 100,
          start: DateTime.utc(2026, 1),
        ),
        _tracker(
          id: 'b',
          host: 'beta.test',
          upload: 300,
          download: 300,
          start: DateTime.utc(2026, 2),
        ),
        _tracker(
          id: 'c',
          host: 'gamma.test',
          download: 50,
          start: DateTime.utc(2026, 3),
        ),
      ],
    );

    await pumpConnections(tester);

    double topOf(String host) =>
        tester.getTopLeft(find.textContaining(host).first).dy;
    expect(topOf('gamma.test'), lessThan(topOf('beta.test')));
    expect(topOf('beta.test'), lessThan(topOf('alpha.test')));
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets('places sort button left of search in the app bar', (
    tester,
  ) async {
    when(core.getConnections).thenAnswer((_) async => const <TrackerInfo>[]);

    await pumpConnections(tester);

    final sortDx = tester.getTopLeft(find.byIcon(Icons.sort)).dx;
    final searchDx = tester.getTopLeft(find.byIcon(Icons.search)).dx;
    final clearDx = tester
        .getTopLeft(find.byIcon(Icons.delete_sweep_outlined))
        .dx;
    expect(sortDx, lessThan(searchDx));
    expect(searchDx, lessThan(clearDx));
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets(
    'toggles sort category and direction from popup menu and persists mode',
    (tester) async {
      var nowMs = 1000;
      var pollCount = 0;
      when(core.getConnections).thenAnswer((_) async {
        pollCount++;
        final fastDownload = pollCount >= 2 ? 10000 : 100;
        return [
          _tracker(
            id: 'a',
            host: 'idle.test',
            download: 5000,
            start: DateTime.utc(2026, 3),
          ),
          _tracker(
            id: 'b',
            host: 'fast.test',
            download: fastDownload,
            start: DateTime.utc(2026, 1),
          ),
          _tracker(
            id: 'c',
            host: 'mid.test',
            download: 2000,
            start: DateTime.utc(2026, 2),
          ),
        ];
      });

      await pumpConnections(tester, speedNowMs: () => nowMs);
      nowMs = 2000;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      double topOf(String host) =>
          tester.getTopLeft(find.textContaining(host).first).dy;

      Future<void> selectOption(String label) async {
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      expect(find.text('Sort by speed'), findsOneWidget);
      expect(find.text('Sort by traffic'), findsOneWidget);
      expect(find.text('Sort by time'), findsOneWidget);
      expect(find.text('Default (Time)'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.text('Sort by speed'));
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.speedDesc,
      );
      expect(topOf('fast.test'), lessThan(topOf('idle.test')));
      expect(topOf('idle.test'), lessThan(topOf('mid.test')));

      await selectOption('Sort by speed');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.speedAsc,
      );
      expect(topOf('mid.test'), lessThan(topOf('idle.test')));
      expect(topOf('idle.test'), lessThan(topOf('fast.test')));

      await selectOption('Sort by speed');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.speedDesc,
      );
      expect(topOf('fast.test'), lessThan(topOf('idle.test')));

      await selectOption('Sort by traffic');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.trafficDesc,
      );
      expect(topOf('fast.test'), lessThan(topOf('idle.test')));
      expect(topOf('idle.test'), lessThan(topOf('mid.test')));

      await selectOption('Sort by traffic');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.trafficAsc,
      );
      expect(topOf('mid.test'), lessThan(topOf('idle.test')));
      expect(topOf('idle.test'), lessThan(topOf('fast.test')));

      await selectOption('Sort by time');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.timeDesc,
      );
      expect(topOf('idle.test'), lessThan(topOf('mid.test')));
      expect(topOf('mid.test'), lessThan(topOf('fast.test')));

      await selectOption('Sort by time');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.timeAsc,
      );
      expect(topOf('fast.test'), lessThan(topOf('mid.test')));
      expect(topOf('mid.test'), lessThan(topOf('idle.test')));

      await selectOption('Default (Time)');
      expect(
        container.read(appSettingProvider).connectionSortMode,
        ConnectionSortMode.defaultTimeDesc,
      );
      expect(topOf('idle.test'), lessThan(topOf('mid.test')));
      expect(topOf('mid.test'), lessThan(topOf('fast.test')));

      expect(tester.takeException(), null);
      await teardownView(tester);
    },
  );

  testWidgets('hides process name when findProcessMode is off', (tester) async {
    when(core.getConnections).thenAnswer(
      (_) async => [
        _tracker(
          id: 'a',
          host: 'alpha.test',
          process: 'Telegram.exe',
        ),
      ],
    );

    await pumpConnections(tester);

    expect(find.text('Telegram.exe'), findsOneWidget);

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(findProcessMode: FindProcessMode.off));
    await tester.pump();

    expect(find.text('Telegram.exe'), findsNothing);
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets('keeps the empty state when core throws', (tester) async {
    when(core.getConnections).thenThrow(StateError('core down'));

    await pumpConnections(tester);

    expect(find.byType(NullStatus), findsOneWidget);
    expect(tester.takeException(), null);

    await teardownView(tester);
  });

  testWidgets('stops polling once the view is disposed', (tester) async {
    when(core.getConnections).thenAnswer((_) async => const <TrackerInfo>[]);

    await pumpConnections(tester);
    await teardownView(tester);
    clearInteractions(core);

    await tester.pump(const Duration(seconds: 3));

    verifyNever(core.getConnections);
  });
}
