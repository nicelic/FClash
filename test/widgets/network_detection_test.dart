import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/dashboard/widgets/network_detection.dart'
    as network_detection;
import 'package:fl_clash/widgets/inherited.dart';
import 'package:fl_clash/widgets/ip_detail_dialog.dart';
import 'package:fl_clash/widgets/ip_risk.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

class _TestNetworkDetection extends NetworkDetection {
  _TestNetworkDetection(this._initial);

  final NetworkDetectionState _initial;
  int probeCount = 0;

  @override
  NetworkDetectionState build() => _initial;

  @override
  IpInfo? get rawIpInfo => _initial.ipInfo;

  @override
  Future<void> probeForDrift() async {
    probeCount++;
  }
}

class _DialogAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri.toString();
    if (uri.contains('scamalytics.com/ip/8.8.8.8')) {
      return ResponseBody.fromString(
        '''
        <div class="score">Fraud Score: 12</div>
        <div class="panel_title">Low Risk</div>
        <table>
          <tr><th>Organization Name</th><td>Google LLC</td></tr>
          <tr><th>ASN</th><td>15169</td></tr>
          <tr><th>Country Code</th><td>US</td></tr>
          <tr><th class="title">Datacenter</th></tr>
          <tr><th>Datacenter</th><td>Yes</td></tr>
        </table>
        ''',
        200,
      );
    }
    if (uri.contains('scamalytics.com/ip/')) {
      return ResponseBody.fromString(
        '''
        <div class="score">Fraud Score: 65</div>
        <div class="panel_title">High Risk</div>
        <table>
          <tr><th>Organization Name</th><td>Company 68c242</td></tr>
          <tr><th>ASN</th><td>142433</td></tr>
          <tr><th>ISP Name</th><td>Datawave Global LLC</td></tr>
          <tr><th>Country Name</th><td>Singapore</td></tr>
          <tr><th>Country Code</th><td>SG</td></tr>
          <tr><th class="title">Datacenter</th></tr>
          <tr><th>Datacenter</th><td>No</td></tr>
          <tr><th class="title">External Blacklists</th></tr>
          <tr><th>Firehol</th><td>No</td></tr>
          <tr><th class="title">Proxies</th></tr>
          <tr><th>Anonymizing VPN</th><td>No</td></tr>
        </table>
        ''',
        200,
      );
    }
    if (uri.contains('ip-api.com') || uri.contains('ipwho.is')) {
      return ResponseBody.fromString(
        '{"query":"94.118.188.128","countryCode":"SG","country":"Singapore","regionName":"North West","city":"Singapore","org":"Company 68c242","isp":"Datawave Global LLC","as":"AS142433 Company 68c242"}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const sampleIp = IpInfo(
    ip: '94.118.188.128',
    countryCode: 'SG',
    country: 'Singapore',
    province: 'North West',
    city: 'Singapore',
    isp: 'Datawave Global LLC',
    asn: 'AS142433',
    asName: 'Company 68c242',
    asDomain: 'datawave.example',
  );

  testWidgets('NetworkDetection renders all 4 card sizes and risk badge', (
    tester,
  ) async {
    const state = NetworkDetectionState(
      isLoading: false,
      ipInfo: sampleIp,
      riskyIp: '94.118.188.128',
      riskLevel: IpRiskLevel.high,
    );

    for (final size in DashboardTileSize.values) {
      await tester.pumpWidget(
        TestApp(
          key: ValueKey(size),
          wrapInProviderScope: true,
          overrides: [
            networkDetectionProvider.overrideWith(
              () => _TestNetworkDetection(state),
            ),
          ],
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: size == DashboardTileSize.wide ||
                        size == DashboardTileSize.large
                    ? 360
                    : 180,
                child: network_detection.NetworkDetection(size: size),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('94.118.188.128'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(tester.takeException(), null);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('NetworkDetection pauses drift probe timer when hidden or paused', (
    tester,
  ) async {
    final notifier = _TestNetworkDetection(
      const NetworkDetectionState(isLoading: false, ipInfo: sampleIp),
    );
    final isActive = ValueNotifier<bool>(true);
    addTearDown(isActive.dispose);

    final container = ProviderContainer(
      overrides: [networkDetectionProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    container
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(ipCheckInterval: IpCheckInterval.oneMinute));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: ValueListenableBuilder<bool>(
            valueListenable: isActive,
            builder: (_, active, _) => PageActivityScope(
              isActive: active,
              child: const Scaffold(body: network_detection.NetworkDetection()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(notifier.probeCount, 1);

    isActive.value = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(notifier.probeCount, 1);

    isActive.value = true;
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(notifier.probeCount, 2);

    container.read(windowVisibleProvider.notifier).value = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(notifier.probeCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('IpDetailDialog toggles to Scamalytics view and queries custom IP', (
    tester,
  ) async {
    final originalAdapter = request.dio.httpClientAdapter;
    request.dio.httpClientAdapter = _DialogAdapter();
    addTearDown(() => request.dio.httpClientAdapter = originalAdapter);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  unawaited(
                    showIpDetailDialog(
                      context,
                      sampleIp.ip,
                      preloaded: sampleIp,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Datawave Global LLC'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(IpRiskScore), findsOneWidget);
    expect(find.text('65'), findsOneWidget);

    await tester.tap(find.text('94.118.188.128'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '8.8.8.8');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Google LLC'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
