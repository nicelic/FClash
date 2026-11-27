import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _ToggleCase {
  final String name;
  final Widget widget;
  final bool Function(ProviderContainer container) read;
  final bool initial;

  const _ToggleCase(this.name, this.widget, this.read, {this.initial = false});
}

final _toggleCases = <_ToggleCase>[
  _ToggleCase(
    'VPN',
    const VPNItem(),
    (c) => c.read(vpnSettingProvider).enable,
    initial: true,
  ),
  _ToggleCase(
    'TUN',
    const TUNItem(),
    (c) => c.read(patchClashConfigProvider).tun.enable,
  ),
  _ToggleCase(
    'allow bypass',
    const AllowBypassItem(),
    (c) => c.read(vpnSettingProvider).allowBypass,
    initial: true,
  ),
  _ToggleCase(
    'vpn system proxy',
    const VpnSystemProxyItem(),
    (c) => c.read(vpnSettingProvider).systemProxy,
    initial: true,
  ),
  _ToggleCase(
    'system proxy',
    const SystemProxyItem(),
    (c) => c.read(networkSettingProvider).systemProxy,
    initial: true,
  ),
  _ToggleCase('ipv6', const Ipv6Item(), (c) => c.read(vpnSettingProvider).ipv6),
  _ToggleCase(
    'auto set system dns',
    const AutoSetSystemDnsItem(),
    (c) => c.read(networkSettingProvider).autoSetSystemDns,
    initial: true,
  ),
  _ToggleCase(
    'dns hijacking',
    const DNSHijackingItem(),
    (c) => c.read(vpnSettingProvider).dnsHijacking,
  ),
  _ToggleCase(
    'tun auto route',
    const TunAutoRouteItem(),
    (c) => c.read(patchClashConfigProvider).tun.autoRoute,
    initial: true,
  ),
  _ToggleCase(
    'tun strict route',
    const TunStrictRouteItem(),
    (c) => c.read(patchClashConfigProvider).tun.strictRoute,
  ),
  _ToggleCase(
    'tun dns hijack',
    const TunDnsHijackItem(),
    (c) => c.read(patchClashConfigProvider).tun.dnsHijack.isNotEmpty,
    initial: true,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
  });

  tearDown(() => container.dispose());

  Future<void> pumpItem(WidgetTester tester, Widget item) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Scaffold(body: ListView(children: [item])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('toggles write to their own setting', () {
    for (final testCase in _toggleCases) {
      testWidgets('${testCase.name} flips both ways', (tester) async {
        await pumpItem(tester, testCase.widget);

        expect(testCase.read(container), testCase.initial);

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(testCase.read(container), !testCase.initial);

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(testCase.read(container), testCase.initial);
      });
    }
  });

  group('option pickers', () {
    testWidgets('the stack picker writes the chosen tun stack', (tester) async {
      await pumpItem(tester, const TunStackItem());
      final initial = container.read(patchClashConfigProvider).tun.stack;
      final target = TunStack.values.firstWhere((item) => item != initial);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(target.name).last);
      await tester.pumpAndSettle();

      expect(container.read(patchClashConfigProvider).tun.stack, target);
    });

    testWidgets('the route mode picker writes the chosen mode', (tester) async {
      await pumpItem(tester, const RouteModeItem());
      final initial = container.read(networkSettingProvider).routeMode;
      final target = RouteMode.values.firstWhere((item) => item != initial);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_routeModeLabel(target)).last);
      await tester.pumpAndSettle();

      expect(container.read(networkSettingProvider).routeMode, target);
    });

    testWidgets('the interface name mode picker writes the chosen mode', (
      tester,
    ) async {
      await pumpItem(tester, const InterfaceNameModeItem());
      final initial = container
          .read(patchClashConfigProvider)
          .interfaceNameMode;
      final target = InterfaceNameMode.values.firstWhere(
        (item) => item != initial,
      );

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_interfaceNameModeLabel(target)).last);
      await tester.pumpAndSettle();

      expect(
        container.read(patchClashConfigProvider).interfaceNameMode,
        target,
      );
    });
  });

  group('interface name visibility', () {
    testWidgets('is hidden unless the mode is custom', (tester) async {
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) =>
                state.copyWith(interfaceNameMode: InterfaceNameMode.follow),
          );

      await pumpItem(tester, const InterfaceNameItem());

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('is shown when the mode is custom', (tester) async {
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) =>
                state.copyWith(interfaceNameMode: InterfaceNameMode.custom),
          );

      await pumpItem(tester, const InterfaceNameItem());

      expect(find.byType(ListTile), findsOneWidget);
    });
  });

  group('network options items', () {
    test('interface name rows appear only on desktop', () {
      final desktopTypes = networkOptionsItems(
        isDesktop: true,
        isMacOS: false,
      ).map((item) => item.runtimeType);
      expect(desktopTypes, contains(InterfaceNameModeItem));
      expect(desktopTypes, contains(InterfaceNameItem));
      expect(desktopTypes, contains(TunAutoRouteItem));
      expect(desktopTypes, contains(TunStrictRouteItem));
      expect(desktopTypes, contains(TunDnsHijackItem));
      expect(desktopTypes, contains(TunInterfaceItem));
      expect(desktopTypes, contains(TunCongestionControllerItem));
      expect(desktopTypes, contains(TunMtuItem));

      final androidTypes = networkOptionsItems(
        isDesktop: false,
        isMacOS: false,
      ).map((item) => item.runtimeType);
      expect(androidTypes, isNot(contains(InterfaceNameModeItem)));
      expect(androidTypes, isNot(contains(InterfaceNameItem)));
      expect(androidTypes, isNot(contains(TunAutoRouteItem)));
      expect(androidTypes, isNot(contains(TunStrictRouteItem)));
      expect(androidTypes, isNot(contains(TunDnsHijackItem)));
      expect(androidTypes, isNot(contains(TunInterfaceItem)));
      expect(androidTypes, contains(TunCongestionControllerItem));
      expect(androidTypes, contains(TunMtuItem));
    });
  });

  group('route address visibility', () {
    testWidgets('is hidden while bypassing private addresses', (tester) async {
      container
          .read(networkSettingProvider.notifier)
          .update(
            (state) => state.copyWith(routeMode: RouteMode.bypassPrivate),
          );

      await pumpItem(tester, const RouteAddressItem());

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('is shown for every other route mode', (tester) async {
      container
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(routeMode: RouteMode.config));

      await pumpItem(tester, const RouteAddressItem());

      expect(find.byType(ListTile), findsOneWidget);
    });
  });

  group('extended tun controls', () {
    testWidgets('tun dns hijack toggle writes udp and tcp any:53 rules', (
      tester,
    ) async {
      await pumpItem(tester, const TunDnsHijackItem());

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(container.read(patchClashConfigProvider).tun.dnsHijack, isEmpty);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        container.read(patchClashConfigProvider).tun.dnsHijack,
        ['any:53', 'tcp://any:53'],
      );
    });

    testWidgets('congestion controller is visible only when stack is mips', (
      tester,
    ) async {
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(stack: TunStack.gvisor));
      await pumpItem(tester, const TunCongestionControllerItem());
      expect(find.byType(ListTile), findsNothing);

      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(stack: TunStack.mips));
      await pumpItem(tester, const TunCongestionControllerItem());
      expect(find.byType(ListTile), findsOneWidget);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TunCongestionController.bbr3.name).last);
      await tester.pumpAndSettle();

      expect(
        container.read(patchClashConfigProvider).tun.congestionController,
        TunCongestionController.bbr3,
      );
    });

    testWidgets('mtu item validates 1280-9000 range and saves integer values', (
      tester,
    ) async {
      await AppLocalizations.load(const Locale('en'));
      await pumpItem(tester, const TunMtuItem());

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1200');
      await tester.pumpAndSettle();
      await tester.tap(find.text(currentAppLocalizations.submit));
      await tester.pumpAndSettle();
      expect(
        container.read(patchClashConfigProvider).tun.mtu,
        defaultTunMtu,
      );

      await tester.enterText(find.byType(TextFormField).first, '1500');
      await tester.pumpAndSettle();
      await tester.tap(find.text(currentAppLocalizations.submit));
      await tester.pumpAndSettle();
      expect(container.read(patchClashConfigProvider).tun.mtu, 1500);
    });

    testWidgets('interface picker lists auto and detected physical interfaces', (
      tester,
    ) async {
      await AppLocalizations.load(const Locale('en'));
      final previous = listNetworkInterfaces;
      addTearDown(() => listNetworkInterfaces = previous);
      listNetworkInterfaces = ({bool includeLoopback = false}) async => [
        _FakeNic('WLAN', [_FakeNicAddress('192.168.1.2')]),
        _FakeNic('Ethernet', [_FakeNicAddress('10.0.0.2')]),
      ];

      await pumpItem(tester, const TunInterfaceItem());
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('WLAN').last);
      await tester.pumpAndSettle();
      var clashConfig = container.read(patchClashConfigProvider);
      expect(clashConfig.interfaceNameMode, InterfaceNameMode.custom);
      expect(clashConfig.interfaceName, 'WLAN');

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(currentAppLocalizations.auto).last);
      await tester.pumpAndSettle();
      clashConfig = container.read(patchClashConfigProvider);
      expect(clashConfig.interfaceNameMode, InterfaceNameMode.clear);
      expect(clashConfig.interfaceName, isEmpty);
    });
  });
}

class _FakeNic implements NetworkInterface {
  _FakeNic(this.name, this.addresses);

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNicAddress implements InterfaceAddress {
  _FakeNicAddress(this.address);

  @override
  final String address;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _routeModeLabel(RouteMode mode) {
  return switch (mode) {
    RouteMode.config => 'Use config',
    RouteMode.bypassPrivate => 'Bypass private addresses',
  };
}

String _interfaceNameModeLabel(InterfaceNameMode mode) {
  return switch (mode) {
    InterfaceNameMode.clear => 'Clear',
    InterfaceNameMode.follow => 'Follow config',
    InterfaceNameMode.custom => 'Custom',
  };
}
