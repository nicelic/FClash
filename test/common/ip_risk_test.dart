import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = '''
<html>
<body>
  <div class="score_bar">
    <div class="score">Fraud Score: 72</div>
    <div class="panel_title">High Risk</div>
  </div>
  <div class="panel_body">
    where we have visibility, we apply a score of 72.
    We see high levels of web traffic from this network, some of which appears to be fraudulent.
    It is operated by <b>Example Host</b> whose web traffic we consider to present a potentially <b>High</b> risk.
    It is owned by <b>Parent Corp</b> whose web traffic we also consider to present a potentially <b>Medium</b> risk.
    Example Host is operating a Anonymizing VPN, which could be proxying traffic from other users.
    Overall, there is potentially a high risk that traffic from this IP is fraudulent.
  </div>
  <table>
    <tr><th class="title">Geo &amp; Network</th></tr>
    <tr><th>Hostname</th><td>edge-1.example.net</td></tr>
    <tr><th>ASN</th><td>142433</td></tr>
    <tr><th>ISP Name</th><td>Example ISP</td></tr>
    <tr><th>Organization Name</th><td>Example Host</td></tr>
    <tr><th>Country Name</th><td>Singapore</td></tr>
    <tr><th>Country Code</th><td>SG</td></tr>
    <tr><th>State / Province</th><td>North West</td></tr>
    <tr><th>City</th><td>Singapore</td></tr>
    <tr><th class="title">Datacenter</th></tr>
    <tr><th>Datacenter</th><td>Unknown</td></tr>
    <tr><th class="title">External Blacklists</th></tr>
    <tr><th>Firehol</th><td>No</td></tr>
    <tr><th>Spamhaus</th><td>Yes</td></tr>
    <tr><th class="title">Proxies</th></tr>
    <tr><th>Anonymizing VPN</th><td>Yes</td></tr>
    <tr><th>Server</th><td>Yes</td></tr>
  </table>
</body>
</html>
''';

void main() {
  test('parses Scamalytics HTML table, note, and gzip payloads', () {
    final gzipped = gzip.encode(utf8.encode(_sampleHtml));
    final risk = parseScamalyticsBytes('94.118.188.128', gzipped);

    expect(risk, isNotNull);
    expect(risk!.ip, '94.118.188.128');
    expect(risk.score, 72);
    expect(risk.level, IpRiskLevel.high);
    expect(risk.asn, 'AS142433');
    expect(risk.isp, 'Example ISP');
    expect(risk.organization, 'Example Host');
    expect(risk.hostname, 'edge-1.example.net');
    expect(risk.countryCode, 'SG');
    expect(risk.checks, contains(
      const IpRiskCheck(
        group: IpRiskGroup.datacenter,
        name: 'Datacenter',
        hit: true,
      ),
    ));
    expect(risk.checks, contains(
      const IpRiskCheck(
        group: IpRiskGroup.blacklist,
        name: 'Spamhaus',
        hit: true,
      ),
    ));
    expect(risk.note?.direct, isTrue);
    expect(risk.note?.amount, IpRiskAmount.high);
    expect(risk.note?.share, IpRiskShare.some);
    expect(risk.note?.operatorName, 'Example Host');
    expect(risk.note?.operatorLevel, IpRiskLevel.high);
    expect(risk.note?.ownerName, 'Parent Corp');
    expect(risk.note?.ownerLevel, IpRiskLevel.medium);
    expect(risk.note?.connection, IpRiskConnection.vpn);
    expect(risk.note?.warning, IpRiskLevel.high);
  });

  test('preserves zero score only for clean home broadband', () {
    const cleanHomeHtml = '''
      <div class="score">Fraud Score: 0</div>
      <div class="panel_title">Low Risk</div>
      <table>
        <tr><th class="title">Datacenter</th></tr>
        <tr><th>Datacenter</th><td>No</td></tr>
      </table>
    ''';
    const unknownHtml = '''
      <div class="score">Fraud Score: 0</div>
      <div class="panel_title">Low Risk</div>
      <table>
        <tr><th class="title">Datacenter</th></tr>
        <tr><th>Datacenter</th><td>Unknown</td></tr>
      </table>
    ''';

    expect(parseScamalytics('1.1.1.1', cleanHomeHtml)?.score, 0);
    expect(parseScamalytics('1.1.1.2', unknownHtml)?.score, 1);
    expect(parseScamalytics('1.1.1.3', '<html>no score</html>'), isNull);
  });

  test('classifies public, LAN, and TUN addresses and formats emojis', () {
    expect(classifyIp('94.118.188.128'), IpCategory.public);
    expect(classifyIp('198.18.0.1'), IpCategory.tun);
    expect(classifyIp('fdfe:dcba:9876::1'), IpCategory.tun);
    expect(classifyIp('10.0.0.108'), IpCategory.lan);
    expect(classifyIp('192.168.1.10'), IpCategory.lan);
    expect(countryCodeToEmoji('sg'), '🇸🇬');
  });
}
