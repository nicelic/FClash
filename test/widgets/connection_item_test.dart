import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

TrackerInfo _tracker({
  String rule = 'DOMAIN-SUFFIX',
  String rulePayload = '',
  String process = '',
  int uid = 0,
  String sourceIP = '',
  String sourcePort = '',
  String destinationIP = '',
  String destinationPort = '',
  String host = '',
  List<String> chains = const [],
}) {
  return TrackerInfo(
    id: '1',
    start: DateTime(2026, 1, 1, 10, 30),
    metadata: Metadata(
      network: 'tcp',
      process: process,
      uid: uid,
      sourceIP: sourceIP,
      sourcePort: sourcePort,
      destinationIP: destinationIP,
      destinationPort: destinationPort,
      host: host,
    ),
    chains: chains,
    rule: rule,
    rulePayload: rulePayload,
  );
}

void main() {
  testWidgets('TrackerInfoDetailView renders formatted connection fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestApp(
        homeBuilder: (child) => Scaffold(body: child),
        child: SheetProvider(
          type: SheetType.page,
          child: TrackerInfoDetailView(
            trackerInfo: _tracker(
              rule: 'DOMAIN-SUFFIX',
              rulePayload: 'example.com',
              process: 'chrome',
              uid: 1000,
              sourceIP: '1.2.3.4',
              sourcePort: '8080',
              destinationIP: '5.6.7.8',
              destinationPort: '443',
              host: 'example.com',
              chains: const ['DIRECT'],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('DOMAIN-SUFFIX(example.com)'), findsOneWidget);
    expect(find.text('chrome(1000)'), findsOneWidget);
    expect(find.text('1.2.3.4:8080'), findsOneWidget);
    expect(find.text('5.6.7.8:443'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('DIRECT'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('DIRECT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TrackerInfoDetailView omits empty fields', (tester) async {
    await tester.pumpWidget(
      TestApp(
        homeBuilder: (child) => Scaffold(body: child),
        child: SheetProvider(
          type: SheetType.page,
          child: TrackerInfoDetailView(trackerInfo: _tracker()),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('('), findsNothing);
    expect(find.text('tcp'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TrackerInfoItem shows all chains and forwards their clicks', (
    tester,
  ) async {
    final clicked = <String>[];
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        homeBuilder: (child) => Scaffold(body: child),
        child: TrackerInfoItem(
          trackerInfo: _tracker(chains: const ['Proxy A', 'Proxy B']),
          detailTitle: 'detail',
          onClickKeyword: clicked.add,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Proxy A'), findsOneWidget);
    expect(find.text('Proxy B'), findsOneWidget);

    await tester.tap(find.text('Proxy A'));
    await tester.pump();
    await tester.tap(find.text('Proxy B'));
    await tester.pump();

    expect(clicked, ['Proxy A', 'Proxy B']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TrackerInfoItem shows live speed and total summary', (
    tester,
  ) async {
    final item = _tracker().copyWith(
      upload: (27.8 * 1024 * 1024).round(),
      download: (6.5 * 1024 * 1024).round(),
      uploadSpeed: 128 * 1024,
      downloadSpeed: (2.4 * 1024 * 1024).round(),
    );

    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        homeBuilder: (child) => Scaffold(body: child),
        child: TrackerInfoItem(trackerInfo: item, detailTitle: 'detail'),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('128KB/s ↑ 2.4MB/s ↓ (27.8MB / 6.5MB)'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TrackerInfoDetailView updates live from stateListenable', (
    tester,
  ) async {
    final initial = _tracker(host: 'example.com').copyWith(
      upload: 1024,
      download: 2048,
      uploadSpeed: 512,
      downloadSpeed: 1024,
    );
    final controller = TrackerInfoListController()..setTrackerInfos([initial]);

    await tester.pumpWidget(
      TestApp(
        homeBuilder: (child) => Scaffold(body: child),
        child: SheetProvider(
          type: SheetType.page,
          child: TrackerInfoDetailView(
            trackerInfo: initial,
            stateListenable: controller,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('512B/s (1KB)'), findsOneWidget);
    expect(find.text('1KB/s (2KB)'), findsOneWidget);

    controller.setTrackerInfos([
      initial.copyWith(
        upload: 4096,
        download: 8192,
        uploadSpeed: 2048,
        downloadSpeed: 4096,
      ),
    ]);
    await tester.pump();

    expect(find.text('2KB/s (4KB)'), findsOneWidget);
    expect(find.text('4KB/s (8KB)'), findsOneWidget);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'TrackerInfoItem shows bare process name below chains only when findProcessMode is always on desktop',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            homeBuilder: (child) => Scaffold(body: child),
            child: TrackerInfoItem(
              trackerInfo: _tracker(
                process: 'Telegram.exe',
                uid: 1000,
                chains: const ['Proxy A'],
              ),
              detailTitle: 'detail',
              supportsProcessIcon: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Telegram.exe'), findsOneWidget);
      expect(find.text('Telegram.exe(1000)'), findsNothing);
      expect(find.byType(PackageIcon), findsNothing);

      final processTop = tester.getTopLeft(find.text('Telegram.exe')).dy;
      final chipBottom = tester.getBottomLeft(find.text('Proxy A')).dy;
      expect(processTop, greaterThanOrEqualTo(chipBottom));

      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(findProcessMode: FindProcessMode.off));
      await tester.pump();

      expect(find.text('Telegram.exe'), findsNothing);
      expect(find.byType(PackageIcon), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TrackerInfoItem shows PackageIcon without text line on icon-capable platforms',
    (tester) async {
      await tester.pumpWidget(
        TestApp(
          wrapInProviderScope: true,
          homeBuilder: (child) => Scaffold(body: child),
          child: TrackerInfoItem(
            trackerInfo: _tracker(
              process: 'com.telegram.messenger',
              chains: const ['Proxy A'],
            ),
            detailTitle: 'detail',
            showProcess: true,
            supportsProcessIcon: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PackageIcon), findsOneWidget);
      expect(find.text('com.telegram.messenger'), findsNothing);

      await tester.pumpWidget(
        TestApp(
          wrapInProviderScope: true,
          homeBuilder: (child) => Scaffold(body: child),
          child: TrackerInfoItem(
            trackerInfo: _tracker(
              process: 'com.telegram.messenger',
              chains: const ['Proxy A'],
            ),
            detailTitle: 'detail',
            showProcess: false,
            supportsProcessIcon: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PackageIcon), findsNothing);
      expect(find.text('com.telegram.messenger'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
