import 'dart:io';

import 'package:fl_clash/common/ip_cache.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  late Directory tempDir;
  late DateTime now;
  late String? previousLocale;
  late IpIntelCache cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ip_cache_test_');
    now = DateTime(2026, 11, 27, 12, 0);
    previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en';
    cache = IpIntelCache(
      directoryResolver: () async => tempDir,
      now: () => now,
    );
  });

  tearDown(() {
    Intl.defaultLocale = previousLocale;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('stores and reads rich IpInfo and IpRisk entries within TTL', () async {
    const info = IpInfo(
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
    const risk = IpRisk(
      ip: '94.118.188.128',
      score: 0,
      level: IpRiskLevel.low,
      isp: 'Datawave Global LLC',
      checks: [
        IpRiskCheck(
          group: IpRiskGroup.datacenter,
          name: 'Datacenter',
          hit: false,
        ),
      ],
    );

    await cache.writeDetail(info);
    await cache.writeRisk(risk);

    expect(await cache.readDetail(info.ip), info);
    expect(await cache.readRisk(info.ip), risk);
  });

  test('expires detail after 24h and risk after 12h', () async {
    const info = IpInfo(ip: '1.1.1.1', countryCode: 'US', country: 'US');
    const risk = IpRisk(ip: '1.1.1.1', score: 35, level: IpRiskLevel.medium);

    await cache.writeDetail(info);
    await cache.writeRisk(risk);

    now = now.add(const Duration(hours: 13));
    expect(await cache.readRisk('1.1.1.1'), isNull);
    expect(await cache.readDetail('1.1.1.1'), info);

    now = now.add(const Duration(hours: 12));
    expect(await cache.readDetail('1.1.1.1'), isNull);
  });

  test('scopes detail cache entries by locale language', () async {
    const enInfo = IpInfo(
      ip: '8.8.8.8',
      countryCode: 'US',
      country: 'United States',
    );
    const zhInfo = IpInfo(ip: '8.8.8.8', countryCode: 'US', country: '美国');

    Intl.defaultLocale = 'en_US';
    await cache.writeDetail(enInfo);
    Intl.defaultLocale = 'zh_CN';
    await cache.writeDetail(zhInfo);

    expect(await cache.readDetail('8.8.8.8'), zhInfo);
    Intl.defaultLocale = 'en_US';
    expect(await cache.readDetail('8.8.8.8'), enInfo);
  });

  test('evicts oldest entries beyond maxEntries', () async {
    for (int i = 0; i < IpIntelCache.maxEntries + 5; i++) {
      now = now.add(const Duration(seconds: 1));
      await cache.writeDetail(
        IpInfo(ip: '198.51.100.$i', countryCode: 'US', country: 'US'),
      );
    }

    expect(await cache.readDetail('198.51.100.0'), isNull);
    expect(
      await cache.readDetail('198.51.100.${IpIntelCache.maxEntries + 4}'),
      isNotNull,
    );
  });

  test('returns null cleanly when cache directory is unavailable', () async {
    final disabled = IpIntelCache(directoryResolver: () async => null);
    await disabled.writeDetail(const IpInfo(ip: '1.1.1.1', countryCode: 'US'));
    expect(await disabled.readDetail('1.1.1.1'), isNull);
    expect(await disabled.readRisk('1.1.1.1'), isNull);
  });
}
