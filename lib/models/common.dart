import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:material_ui/material_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';

part 'generated/common.freezed.dart';

part 'generated/common.g.dart';

@freezed
abstract class NavigationItem with _$NavigationItem {
  const factory NavigationItem({
    required Icon icon,
    required PageLabel label,
    required WidgetBuilder builder,
    @Default(true) bool keep,
    String? path,
    @Default([NavigationItemMode.mobile, NavigationItemMode.desktop])
    List<NavigationItemMode> modes,
  }) = _NavigationItem;
}

@freezed
abstract class Package with _$Package {
  const factory Package({
    required String packageName,
    required String label,
    required bool system,
    required bool internet,
    required int lastUpdateTime,
  }) = _Package;

  factory Package.fromJson(Map<String, Object?> json) =>
      _$PackageFromJson(json);
}

extension PackagesExt on List<Package> {
  List<Package> getViewList({
    required List<String> pinedList,
    required AccessSortType sortType,
    required bool isFilterSystemApp,
    required bool isFilterNonInternetApp,
  }) {
    return where(
      (item) =>
          (isFilterSystemApp ? item.system == false : true) &&
          (isFilterNonInternetApp ? item.internet == true : true),
    ).sorted((a, b) {
      final isSelectA = pinedList.contains(a.packageName);
      final isSelectB = pinedList.contains(b.packageName);

      if (isSelectA != isSelectB) {
        return isSelectA ? -1 : 1;
      }
      return switch (sortType) {
        AccessSortType.none => 0,
        AccessSortType.name => a.label.compareTo(b.label),
        AccessSortType.time => b.lastUpdateTime.compareTo(a.lastUpdateTime),
      };
    });
  }
}

@freezed
abstract class Metadata with _$Metadata {
  const factory Metadata({
    @Default(0) int uid,
    @Default('') String network,
    @Default('') String sourceIP,
    @Default('') String sourcePort,
    @Default('') String destinationIP,
    @Default('') String destinationPort,
    @Default('') String host,
    DnsMode? dnsMode,
    @Default('') String process,
    @Default('') String processPath,
    @Default('') String remoteDestination,
    @Default([]) List<String> sourceGeoIP,
    @Default([]) List<String> destinationGeoIP,
    @Default('') String destinationIPASN,
    @Default('') String sourceIPASN,
    @Default('') String specialRules,
    @Default('') String specialProxy,
  }) = _Metadata;

  factory Metadata.fromJson(Map<String, Object?> json) =>
      _$MetadataFromJson(json);
}

@freezed
abstract class TrackerInfo with _$TrackerInfo {
  const factory TrackerInfo({
    required String id,
    @Default(0) int upload,
    @Default(0) int download,
    required DateTime start,
    required Metadata metadata,
    required List<String> chains,
    required String rule,
    required String rulePayload,
    int? downloadSpeed,
    int? uploadSpeed,
  }) = _TrackerInfo;

  factory TrackerInfo.fromJson(Map<String, Object?> json) =>
      _$TrackerInfoFromJson(json);
}

extension TrackerInfoExt on TrackerInfo {
  String get title {
    final host = metadata.host;
    if (host.isNotEmpty) {
      return host;
    }
    return metadata.destinationIP;
  }

  String get desc {
    var text = '${metadata.network}://';
    final ips = [
      metadata.host,
      metadata.destinationIP,
    ].where((ip) => ip.isNotEmpty);
    text += ips.join('/');
    text += ':${metadata.destinationPort}';
    return text;
  }

  String get progressText {
    final process = metadata.process;
    final uid = metadata.uid;
    if (uid != 0) {
      return '$process($uid)'.trim();
    }
    return process.trim();
  }

  String get trafficSummary {
    final upSpeed = uploadSpeed;
    final downSpeed = downloadSpeed;
    if (upSpeed != null && downSpeed != null) {
      return '${upSpeed.traffic.show}/s ↑ '
          '${downSpeed.traffic.show}/s ↓ '
          '(${upload.traffic.show} / ${download.traffic.show})';
    }
    return Traffic(up: upload, down: download).desc;
  }
}

String _logDateTime(dynamic _) {
  return DateTime.now().showFull;
}

@freezed
abstract class Log with _$Log {
  const factory Log({
    @JsonKey(name: 'LogLevel') @Default(LogLevel.info) LogLevel logLevel,
    @JsonKey(name: 'Payload') @Default('') String payload,
    @JsonKey(fromJson: _logDateTime) required String dateTime,
  }) = _Log;

  factory Log.app(String payload) {
    return Log(payload: payload, dateTime: _logDateTime(null));
  }

  factory Log.fromJson(Map<String, Object?> json) => _$LogFromJson(json);
}

@freezed
abstract class LogsState with _$LogsState {
  const factory LogsState({
    @Default([]) List<Log> logs,
    @Default([]) List<String> keywords,
    @Default('') String query,
    @Default(true) bool autoScrollToEnd,
  }) = _LogsState;
}

extension LogsStateExt on LogsState {
  List<Log> get list {
    final lowQuery = query.toLowerCase();
    return logs.where((log) {
      final logLevelName = log.logLevel.name;
      return {logLevelName}.containsAll(keywords) &&
          ((log.payload.toLowerCase().contains(lowQuery)) ||
              logLevelName.contains(lowQuery));
    }).toList();
  }
}

@freezed
abstract class TrackerInfosState with _$TrackerInfosState {
  const factory TrackerInfosState({
    @Default([]) List<TrackerInfo> trackerInfos,
    @Default([]) List<String> keywords,
    @Default('') String query,
    @Default(true) bool autoScrollToEnd,
  }) = _TrackerInfosState;
}

extension TrackerInfosStateExt on TrackerInfosState {
  List<TrackerInfo> get list {
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty && keywords.isEmpty) {
      return trackerInfos;
    }
    return trackerInfos.where((trackerInfo) {
      final metadata = trackerInfo.metadata;
      final process = metadata.process;
      final chains = trackerInfo.chains;
      if (keywords.isNotEmpty) {
        for (final keyword in keywords) {
          if (keyword != process && !chains.contains(keyword)) {
            return false;
          }
        }
      }
      if (lowerQuery.isEmpty) {
        return true;
      }
      return metadata.network.toLowerCase().contains(lowerQuery) ||
          metadata.host.toLowerCase().contains(lowerQuery) ||
          metadata.destinationIP.toLowerCase().contains(lowerQuery) ||
          process.toLowerCase().contains(lowerQuery) ||
          chains.any((chain) => chain.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}

const defaultDavFileName = 'backup.zip';
const _davPasswordFormatVersion = 'v1';
const _davPasswordNonceLength = 16;
const _davPasswordObfuscationMask = <int>[
  0x9d,
  0x42,
  0xe7,
  0x1b,
  0x68,
  0xb4,
  0x35,
  0xca,
  0x7f,
  0x20,
  0xd1,
  0x56,
  0x83,
  0xfa,
  0x0c,
  0xa9,
];

// This only prevents accidental plain-text disclosure. It is deliberately not
// a security boundary against reverse engineering or same-user access.
String _encodeDavPassword(String password) {
  if (password.isEmpty) {
    return '';
  }
  final random = Random.secure();
  final nonce = List<int>.generate(
    _davPasswordNonceLength,
    (_) => random.nextInt(256),
    growable: false,
  );
  final passwordBytes = utf8.encode(password);
  final obfuscated = List<int>.generate(
    passwordBytes.length,
    (index) =>
        passwordBytes[index] ^
        nonce[index % nonce.length] ^
        _davPasswordObfuscationMask[index % _davPasswordObfuscationMask.length],
    growable: false,
  );
  return [
    _davPasswordFormatVersion,
    base64UrlEncode(nonce),
    base64UrlEncode(obfuscated),
  ].join('.');
}

String _decodeDavPassword(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  final parts = value.split('.');
  if (parts.length != 3 || parts[0] != _davPasswordFormatVersion) {
    return value;
  }
  try {
    final nonce = base64Url.decode(parts[1]);
    final obfuscated = base64Url.decode(parts[2]);
    if (nonce.length != _davPasswordNonceLength) {
      return '';
    }
    final passwordBytes = List<int>.generate(
      obfuscated.length,
      (index) =>
          obfuscated[index] ^
          nonce[index % nonce.length] ^
          _davPasswordObfuscationMask[index %
              _davPasswordObfuscationMask.length],
      growable: false,
    );
    return utf8.decode(passwordBytes);
  } on FormatException {
    return '';
  }
}

@Freezed(toStringOverride: false)
abstract class DAVProps with _$DAVProps {
  const DAVProps._();

  const factory DAVProps({
    required String uri,
    required String user,
    @JsonKey(fromJson: _decodeDavPassword, toJson: _encodeDavPassword)
    @Default('')
    String password,
    @Default(defaultDavFileName) String fileName,
  }) = _DAVProps;

  factory DAVProps.fromJson(Map<String, Object?> json) =>
      _$DAVPropsFromJson(json);

  @override
  String toString() =>
      'DAVProps(uri: $uri, user: $user, password: ***, fileName: $fileName)';
}

@freezed
abstract class FileInfo with _$FileInfo {
  const factory FileInfo({required int size, DateTime? lastModified}) =
      _FileInfo;
}

extension FileInfoFileExt on File {
  Future<FileInfo?> getFileInfo() async {
    if (!await exists()) {
      return null;
    }
    final size = await length();
    final lastModified = await _getValidLastModified();
    return FileInfo(size: size, lastModified: lastModified);
  }

  Future<DateTime?> _getValidLastModified() async {
    try {
      final value = await lastModified();
      return value.year > 1970 ? value : null;
    } on FileSystemException {
      return null;
    }
  }
}

extension FileInfoExt on FileInfo {
  String getDesc(BuildContext context) {
    final lastModifiedDesc =
        lastModified?.getLastUpdateTimeDesc(context) ??
        context.appLocalizations.unknown;
    return '${size.traffic.show}  ·  $lastModifiedDesc';
  }
}

@freezed
abstract class VersionInfo with _$VersionInfo {
  const factory VersionInfo({
    @Default('') String clashName,
    @Default('') String version,
  }) = _VersionInfo;

  factory VersionInfo.fromJson(Map<String, Object?> json) =>
      _$VersionInfoFromJson(json);
}

@freezed
abstract class Traffic with _$Traffic {
  const factory Traffic({@Default(0) num up, @Default(0) num down}) = _Traffic;

  factory Traffic.fromJson(Map<String, Object?> json) =>
      _$TrafficFromJson(json);
}

extension TrafficExt on Traffic {
  String get speedText {
    return '↑ ${up.traffic.show}/s   ↓ ${down.traffic.show}/s';
  }

  String get desc {
    return '${up.traffic.show} ↑ ${down.traffic.show} ↓';
  }

  String get trayTitle {
    return '${up.shortTraffic.show}/s\n${down.shortTraffic.show}/s';
  }

  num get speed => up + down;
}

@freezed
abstract class TrafficShow with _$TrafficShow {
  const factory TrafficShow({required String value, required String unit}) =
      _TrafficShow;
}

extension TrafficShowExt on TrafficShow {
  String get show => '$value$unit';
}

@freezed
abstract class Group with _$Group {
  const factory Group({
    @JsonKey(fromJson: GroupType.parse) required GroupType type,
    @Default([]) List<Proxy> all,
    String? now,
    bool? hidden,
    String? testUrl,
    @Default('') String icon,
    required String name,
  }) = _Group;

  factory Group.fromJson(Map<String, Object?> json) => _$GroupFromJson(json);
}

extension GroupsExt on List<Group> {
  Group? getGroup(String groupName) {
    final index = indexWhere((element) => element.name == groupName);
    return index != -1 ? this[index] : null;
  }
}

extension GroupExt on Group {
  String get realNow => now ?? '';

  String getCurrentSelectedName(String proxyName) {
    if (type.isComputedSelected) {
      return realNow.isNotEmpty ? realNow : proxyName;
    }
    return proxyName.isNotEmpty ? proxyName : realNow;
  }
}

@freezed
abstract class ColorSchemes with _$ColorSchemes {
  const factory ColorSchemes({
    ColorScheme? lightColorScheme,
    ColorScheme? darkColorScheme,
  }) = _ColorSchemes;
}

extension ColorSchemesExt on ColorSchemes {
  ColorScheme getColorSchemeForBrightness(
    Brightness brightness,
    DynamicSchemeVariant schemeVariant,
  ) {
    if (brightness == Brightness.dark) {
      return darkColorScheme != null
          ? ColorScheme.fromSeed(
              seedColor: darkColorScheme!.primary,
              brightness: Brightness.dark,
              dynamicSchemeVariant: schemeVariant,
            )
          : ColorScheme.fromSeed(
              seedColor: const Color(defaultPrimaryColor),
              brightness: Brightness.dark,
              dynamicSchemeVariant: schemeVariant,
            );
    }
    return lightColorScheme != null
        ? ColorScheme.fromSeed(
            seedColor: lightColorScheme!.primary,
            dynamicSchemeVariant: schemeVariant,
          )
        : ColorScheme.fromSeed(
            seedColor: const Color(defaultPrimaryColor),
            dynamicSchemeVariant: schemeVariant,
          );
  }
}

@freezed
abstract class IpRiskCheck with _$IpRiskCheck {
  const factory IpRiskCheck({
    required IpRiskGroup group,
    required String name,
    bool? hit,
  }) = _IpRiskCheck;

  factory IpRiskCheck.fromJson(Map<String, Object?> json) =>
      _$IpRiskCheckFromJson(json);
}

@freezed
abstract class IpRiskNote with _$IpRiskNote {
  const factory IpRiskNote({
    bool? direct,
    @Default('') String isp,
    IpRiskAmount? amount,
    IpRiskShare? share,
    @Default('') String operatorName,
    IpRiskLevel? operatorLevel,
    @Default('') String ownerName,
    IpRiskLevel? ownerLevel,
    IpRiskConnection? connection,
    IpRiskLevel? warning,
  }) = _IpRiskNote;

  factory IpRiskNote.fromJson(Map<String, Object?> json) =>
      _$IpRiskNoteFromJson(json);
}

@freezed
abstract class IpRisk with _$IpRisk {
  const factory IpRisk({
    required String ip,
    required int score,
    required IpRiskLevel level,
    @Default('') String hostname,
    @Default('') String asn,
    @Default('') String isp,
    @Default('') String organization,
    @Default('') String country,
    @Default('') String countryCode,
    @Default('') String region,
    @Default('') String city,
    @Default([]) List<IpRiskCheck> checks,
    IpRiskNote? note,
  }) = _IpRisk;

  factory IpRisk.fromJson(Map<String, Object?> json) => _$IpRiskFromJson(json);
}

extension IpRiskExt on IpRisk {
  bool get isHomeBroadband {
    final datacenter = checks.where(
      (check) => check.group == IpRiskGroup.datacenter,
    );
    return datacenter.isNotEmpty &&
        datacenter.every((check) => check.hit == false) &&
        checks.every((check) => check.hit != true);
  }

  int get displayScore => !isHomeBroadband && score == 0 ? 1 : score;

  IpRisk get normalized =>
      !isHomeBroadband && score == 0 ? copyWith(score: 1) : this;
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _extractAsn(Object? value) {
  final raw = _nonEmptyString(value);
  if (raw == null) {
    return null;
  }
  final match = RegExp(r'^(AS\d+)', caseSensitive: false).firstMatch(raw);
  if (match != null) {
    return match.group(1)!.toUpperCase();
  }
  if (RegExp(r'^\d+$').hasMatch(raw)) {
    return 'AS$raw';
  }
  return null;
}

(String? asn, String? orgName) _splitOrgAsn(Object? value) {
  final raw = _nonEmptyString(value);
  if (raw == null) {
    return (null, null);
  }
  final match = RegExp(
    r'^(AS\d+)\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    return (null, raw);
  }
  final asn = match.group(1)!.toUpperCase();
  final rest = _nonEmptyString(match.group(2));
  return (asn, rest);
}

@freezed
abstract class IpInfo with _$IpInfo {
  const factory IpInfo({
    required String ip,
    required String countryCode,
    String? country,
    String? province,
    String? city,
    String? isp,
    String? asn,
    String? asName,
    String? asDomain,
  }) = _IpInfo;

  factory IpInfo.fromJson(Map<String, Object?> json) => _$IpInfoFromJson(json);

  static String normalizeCountryCode(
    String countryCode, [
    String? country,
    String? province,
  ]) {
    final clean = countryCode.trim().toUpperCase();
    if (clean.length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(clean)) {
      if (clean == 'CN') {
        if (_isTaiwanLabel(province) || _isTaiwanLabel(country)) {
          return 'TW';
        }
        if (province == '香港' || country == '香港') return 'HK';
        if (province == '澳门' ||
            province == '澳門' ||
            country == '澳门' ||
            country == '澳門') {
          return 'MO';
        }
      }
      return clean;
    }
    if (_isTaiwanLabel(clean) ||
        _isTaiwanLabel(country) ||
        _isTaiwanLabel(province)) {
      return 'TW';
    }
    if (clean == 'HK' ||
        clean == 'HKG' ||
        country == '香港' ||
        province == '香港') {
      return 'HK';
    }
    if (clean == 'MO' ||
        clean == 'MAC' ||
        clean == 'MFM' ||
        country == '澳门' ||
        country == '澳門' ||
        province == '澳门' ||
        province == '澳門') {
      return 'MO';
    }
    return clean;
  }

  static String? normalizeCountry(
    String? country, [
    String? countryCode,
    String? province,
  ]) {
    final effectiveCode = countryCode?.trim().toUpperCase();
    if (country == null || country.trim().isEmpty) {
      if (effectiveCode == 'TW' || _isTaiwanLabel(province)) {
        return '台湾 (中国)';
      }
      return null;
    }
    final trimmed = country.trim();
    if (trimmed == '台湾 (中国)' ||
        trimmed == '台灣 (中国)' ||
        trimmed == '臺灣 (中国)' ||
        trimmed == 'Taiwan (China)' ||
        trimmed == '中国台湾' ||
        trimmed == '中國台灣' ||
        trimmed == '中國臺灣') {
      return trimmed;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'taiwan' ||
        lower == 'republic of china' ||
        lower == 'republic of china (taiwan)' ||
        lower == 'taiwan (roc)' ||
        lower == 'taiwan, roc' ||
        lower == 'roc' ||
        lower == 'taiwan, province of china' ||
        lower == 'taiwan, china') {
      return 'Taiwan (China)';
    }
    if (trimmed == '中華民國' ||
        trimmed.contains('中華民國') ||
        trimmed == '台灣' ||
        trimmed == '臺灣') {
      return '台灣 (中国)';
    }
    if (trimmed == '中华民国' ||
        trimmed.contains('中华民国') ||
        trimmed == '台湾') {
      return '台湾 (中国)';
    }
    if (trimmed == '台湾省') {
      return '台湾省 (中国)';
    }
    if (trimmed == '台灣省' || trimmed == '臺灣省') {
      return '台灣省 (中国)';
    }
    return trimmed;
  }

  static bool _isTaiwanLabel(String? text) {
    if (text == null || text.trim().isEmpty) {
      return false;
    }
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    return lower == 'tw' ||
        lower == 'twn' ||
        lower == 'taiwan' ||
        lower.contains('taiwan') ||
        trimmed.contains('台湾') ||
        trimmed.contains('台灣') ||
        trimmed.contains('臺灣') ||
        trimmed.contains('中华民国') ||
        trimmed.contains('中華民國');
  }

  static IpInfo fromIpInfoIoJson(Map<String, dynamic> json) {
    if (json case {'ip': final String ip, 'country': final String country}) {
      final (asn, orgName) = _splitOrgAsn(json['org']);
      final countryName = _nonEmptyString(json['country_name']);
      final province = _nonEmptyString(json['region']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(country, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, country, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: orgName,
        asn: asn,
        asName: orgName,
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromIpApiCoJson(Map<String, dynamic> json) {
    if (json case {
      'ip': final String ip,
      'country_code': final String countryCode,
    }) {
      final countryName = _nonEmptyString(json['country_name']);
      final province = _nonEmptyString(json['region']);
      final org = _nonEmptyString(json['org']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: org,
        asn: _extractAsn(json['asn']),
        asName: org,
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromIpSbJson(Map<String, dynamic> json) {
    if (json case {
      'ip': final String ip,
      'country_code': final String countryCode,
    }) {
      final countryName = _nonEmptyString(json['country']);
      final province = _nonEmptyString(json['region']);
      final org =
          _nonEmptyString(json['organization']) ?? _nonEmptyString(json['isp']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: _nonEmptyString(json['isp']) ?? org,
        asn: _extractAsn(json['asn']),
        asName: _nonEmptyString(json['asn_organization']) ?? org,
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromIpWhoIsJson(Map<String, dynamic> json) {
    if (json['success'] == false) {
      throw const FormatException('invalid json');
    }
    if (json case {
      'ip': final String ip,
      'country_code': final String countryCode,
    }) {
      final conn = json['connection'];
      final connMap = conn is Map ? conn : null;
      final countryName = _nonEmptyString(json['country']);
      final province = _nonEmptyString(json['region']);
      final org = _nonEmptyString(connMap?['org']);
      final isp = _nonEmptyString(connMap?['isp']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: isp ?? org,
        asn: _extractAsn(connMap?['asn']),
        asName: org ?? isp,
        asDomain: _nonEmptyString(connMap?['domain']),
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromMyIpJson(Map<String, dynamic> json) {
    if (json case {'ip': final String ip, 'cc': final String countryCode}) {
      final countryName = _nonEmptyString(json['country']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode),
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromIpAPIJson(Map<String, dynamic> json) {
    if (json['status'] != null && json['status'] != 'success') {
      throw FormatException('ip-api failed: ${json['message']}');
    }
    if (json case {
      'query': final String ip,
      'countryCode': final String countryCode,
    }) {
      final countryName = _nonEmptyString(json['country']);
      final province =
          _nonEmptyString(json['regionName']) ?? _nonEmptyString(json['region']);
      final (_, asLabel) = _splitOrgAsn(json['as']);
      final org = _nonEmptyString(json['org']);
      final isp = _nonEmptyString(json['isp']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: isp,
        asn: _extractAsn(json['as'] ?? json['asn']),
        asName: org ?? asLabel ?? isp,
        asDomain: _nonEmptyString(json['asname']),
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromIdentMeJson(Map<String, dynamic> json) {
    if (json case {'ip': final String ip, 'cc': final String countryCode}) {
      final countryName = _nonEmptyString(json['country']);
      final province = _nonEmptyString(json['region']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: _nonEmptyString(json['aso']),
        asn: _extractAsn(json['asn']),
        asName: _nonEmptyString(json['aso']),
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromGeoJsJson(Map<String, dynamic> json) {
    if (json case {
      'ip': final String ip,
      'country_code': final String countryCode,
    }) {
      final countryName = _nonEmptyString(json['country']);
      final province = _nonEmptyString(json['region']);
      final org = _nonEmptyString(json['organization_name']) ??
          _nonEmptyString(json['organization']);
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode, countryName, province),
        country: countryName == null
            ? null
            : normalizeCountry(countryName, countryCode, province),
        province: province,
        city: _nonEmptyString(json['city']),
        isp: org,
        asn: _extractAsn(json['asn']),
        asName: org,
      );
    }
    throw const FormatException('invalid json');
  }

  static IpInfo fromCloudflareTrace(String traceText) {
    String? ip;
    String? countryCode;
    for (final line in traceText.split('\n')) {
      final parts = line.split('=');
      if (parts.length != 2) continue;
      final key = parts[0].trim();
      final value = parts[1].trim();
      if (key == 'ip') {
        ip = value;
      } else if (key == 'loc') {
        countryCode = value;
      }
    }
    if (ip != null && ip.isNotEmpty) {
      return IpInfo(
        ip: ip,
        countryCode: normalizeCountryCode(countryCode ?? ''),
      );
    }
    throw const FormatException('invalid cloudflare trace');
  }
}

extension IpInfoExt on IpInfo {
  bool get hasDetails =>
      (country?.isNotEmpty ?? false) ||
      (city?.isNotEmpty ?? false) ||
      (asn?.isNotEmpty ?? false) ||
      (asName?.isNotEmpty ?? false) ||
      (isp?.isNotEmpty ?? false);

  IpInfo merge(IpInfo other) {
    final mergedIp = ip.isNotEmpty ? ip : other.ip;
    final sameIp = ip.isEmpty || other.ip.isEmpty || ip == other.ip;
    final mergedCc = countryCode.isNotEmpty
        ? countryCode
        : (sameIp ? other.countryCode : '');
    if (!sameIp) {
      return this;
    }
    return copyWith(
      ip: mergedIp,
      countryCode: mergedCc,
      country: (country?.isNotEmpty ?? false) ? country : other.country,
      province: (province?.isNotEmpty ?? false) ? province : other.province,
      city: (city?.isNotEmpty ?? false) ? city : other.city,
      isp: (isp?.isNotEmpty ?? false) ? isp : other.isp,
      asn: (asn?.isNotEmpty ?? false) ? asn : other.asn,
      asName: (asName?.isNotEmpty ?? false) ? asName : other.asName,
      asDomain: (asDomain?.isNotEmpty ?? false) ? asDomain : other.asDomain,
    );
  }
}

@freezed
abstract class HotKeyAction with _$HotKeyAction {
  const factory HotKeyAction({
    required HotAction action,
    int? key,
    @Default({}) Set<KeyboardModifier> modifiers,
  }) = _HotKeyAction;

  factory HotKeyAction.fromJson(Map<String, Object?> json) =>
      _$HotKeyActionFromJson(json);
}

typedef Validator = String? Function(String? value);

@freezed
abstract class Field with _$Field {
  const factory Field({
    required String label,
    required String value,
    Validator? validator,
  }) = _Field;
}

class CloseWindowIntent extends Intent {
  const CloseWindowIntent();
}

class EscapeBackIntent extends Intent {
  const EscapeBackIntent();
}

@freezed
abstract class Result<T> with _$Result<T> {
  const factory Result({
    required T? data,
    required ResultType type,
    required String message,
  }) = _Result;

  factory Result.success(T data) =>
      Result(data: data, type: ResultType.success, message: '');

  factory Result.error(String message) =>
      Result(data: null, type: ResultType.error, message: message);
}

extension ResultExt on Result {
  bool get isError => type == ResultType.error;

  bool get isSuccess => type == ResultType.success;
}

@freezed
abstract class Script with _$Script {
  const factory Script({
    required int id,
    required String label,
    required DateTime lastUpdateTime,
  }) = _Script;

  factory Script.fromJson(Map<String, Object?> json) => _$ScriptFromJson(json);

  factory Script.create({required String label}) {
    return Script(
      id: snowflake.id,
      label: label,
      lastUpdateTime: DateTime.now(),
    );
  }
}

extension ScriptsExt on List<Script> {
  Script? get(int? id) {
    if (id == null) {
      return null;
    }
    final index = indexWhere((script) => script.id == id);
    if (index != -1) {
      return this[index];
    }
    return null;
  }
}

extension ScriptExt on Script {
  String get fileName => '$id.js';

  Future<String> get path async => appPath.getScriptPath(id.toString());

  Future<String?> get content async {
    final file = File(await path);
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }

  Future<Script> save(String content) async {
    final file = File(await path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(content);
    return copyWith(lastUpdateTime: DateTime.now());
  }

  Future<Script> saveWithPath(String copyPath) async {
    final file = File(await path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await File(copyPath).copy(copyPath);
    return copyWith(lastUpdateTime: DateTime.now());
  }
}

@freezed
abstract class DelayState with _$DelayState {
  const factory DelayState({required int delay, required bool group}) =
      _DelayState;
}

extension DelayStateExt on DelayState {
  int get priority {
    if (delay > 0) return 0;
    if (delay == 0) return 1;
    return 2;
  }

  int compareTo(DelayState other) {
    if (priority != other.priority) {
      return priority.compareTo(other.priority);
    }
    if (delay != other.delay) {
      return delay.compareTo(other.delay);
    }
    if (group && !other.group) return -1;
    if (!group && other.group) return 1;
    return 0;
  }
}

@freezed
abstract class UpdatingMessage with _$UpdatingMessage {
  const factory UpdatingMessage({
    required String label,
    required String message,
  }) = _UpdatingMessage;
}

@freezed
abstract class IconButtonData with _$IconButtonData {
  const factory IconButtonData({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) = _IconButtonData;
}
