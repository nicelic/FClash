import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

part 'generated/app.g.dart';

@Riverpod(keepAlive: true)
class AuthorizedTunEnable extends _$AuthorizedTunEnable
    with AutoDisposeNotifierMixin {
  @override
  TunAuthorizationState build() {
    return TunAuthorizationState.none;
  }
}

@Riverpod(keepAlive: true)
class Logs extends _$Logs with AutoDisposeNotifierMixin {
  @override
  FixedList<Log> build() {
    return FixedList(maxLogsLength);
  }

  void add(Log value) {
    if (!ref.mounted) {
      return;
    }
    this.value = state.append(value);
  }

  Future<bool> exportLogs() async {
    final logString = await encodeLogsTask(value.list);
    final tempFilePath = await appPath.tempFilePath;
    final file = File(tempFilePath);
    await file.safeWriteAsString(logString);
    bool res = false;
    res = await picker.saveFileWithPath(logFileName, tempFilePath) != null;
    return res;
  }
}

@Riverpod(keepAlive: true)
class Requests extends _$Requests with AutoDisposeNotifierMixin {
  @override
  FixedList<TrackerInfo> build() {
    return FixedList(maxRequestsLength);
  }

  void addRequest(TrackerInfo value) {
    if (!ref.mounted) {
      return;
    }
    this.value = state.append(value);
  }
}

@Riverpod(keepAlive: true)
class Providers extends _$Providers with AutoDisposeNotifierMixin {
  @override
  List<ExternalProvider> build() {
    return [];
  }

  void setProvider(ExternalProvider? provider) {
    if (provider == null) return;
    final index = value.indexWhere((item) => item.name == provider.name);
    if (index == -1) return;
    final newState = List<ExternalProvider>.from(value)..[index] = provider;
    value = newState;
  }

  Future<void> syncProviders() async {
    value = await ref.read(coreHandlerProvider).getExternalProviders();
  }
}

@Riverpod(keepAlive: true)
class Packages extends _$Packages with AutoDisposeNotifierMixin {
  @override
  List<Package> build() {
    return [];
  }
}

@Riverpod(keepAlive: true)
class SystemBrightness extends _$SystemBrightness
    with AutoDisposeNotifierMixin {
  @override
  Brightness build() {
    return Brightness.dark;
  }
}

@Riverpod(keepAlive: true)
class Traffics extends _$Traffics with AutoDisposeNotifierMixin {
  @override
  FixedList<Traffic> build() {
    return FixedList(trafficSampleLength);
  }

  void addTraffic(Traffic value) {
    if (!ref.mounted) {
      return;
    }
    this.value = state.append(value);
  }

  void clear() {
    value = state.copyWith()..clear();
  }
}

@Riverpod(keepAlive: true)
class TotalTraffic extends _$TotalTraffic with AutoDisposeNotifierMixin {
  @override
  Traffic build() {
    return const Traffic();
  }
}

@Riverpod(keepAlive: true)
class LoadedLocale extends _$LoadedLocale with AutoDisposeNotifierMixin {
  @override
  Locale? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class LocalIp extends _$LocalIp with AutoDisposeNotifierMixin {
  @override
  String? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class RunTime extends _$RunTime with AutoDisposeNotifierMixin {
  @override
  int? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class ViewSize extends _$ViewSize with AutoDisposeNotifierMixin {
  @override
  Size build() {
    return Size.zero;
  }
}

@Riverpod(keepAlive: true)
class SideWidth extends _$SideWidth with AutoDisposeNotifierMixin {
  @override
  double build() {
    return 0;
  }
}

@Riverpod(keepAlive: true)
double viewWidth(Ref ref) {
  return ref.watch(viewSizeProvider).width;
}

@Riverpod(keepAlive: true)
ViewMode viewMode(Ref ref) {
  return getViewMode(ref.watch(viewWidthProvider));
}

@Riverpod(keepAlive: true)
bool isMobileView(Ref ref) {
  return ref.watch(viewModeProvider) == ViewMode.mobile;
}

@Riverpod(keepAlive: true)
double viewHeight(Ref ref) {
  return ref.watch(viewSizeProvider).height;
}

@Riverpod(keepAlive: true)
class Init extends _$Init with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

@Riverpod(keepAlive: true)
class CurrentPageLabel extends _$CurrentPageLabel
    with AutoDisposeNotifierMixin {
  @override
  PageLabel build() {
    return PageLabel.dashboard;
  }

  void toPage(PageLabel pageLabel) {
    value = pageLabel;
  }

  void toProfiles() {
    toPage(PageLabel.profiles);
  }
}

@Riverpod(keepAlive: true)
class SortNum extends _$SortNum with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int add() => state++;
}

@Riverpod(keepAlive: true)
class CheckIpNum extends _$CheckIpNum with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }

  int add() => state++;
}

@Riverpod(keepAlive: true)
class Version extends _$Version with AutoDisposeNotifierMixin {
  @override
  int build() {
    return 0;
  }
}

@Riverpod(keepAlive: true)
Future<String> coreVersion(Ref ref) async {
  final coreStatus = ref.watch(coreStatusProvider);
  if (coreStatus != CoreStatus.connected) {
    return '';
  }
  try {
    return await ref.read(coreHandlerProvider).getCoreVersion();
  } catch (_) {
    return '';
  }
}

@Riverpod(keepAlive: true)
class Groups extends _$Groups with AutoDisposeNotifierMixin {
  @override
  List<Group> build() {
    return [];
  }
}

@Riverpod(keepAlive: true)
class DelayDataSource extends _$DelayDataSource with AutoDisposeNotifierMixin {
  @override
  DelayMap build() {
    return {};
  }

  void setDelay(Delay delay) {
    if (state[delay.url]?[delay.name] != delay.value) {
      final DelayMap newDelayMap = Map.from(state);
      if (newDelayMap[delay.url] == null) {
        newDelayMap[delay.url] = {};
      }
      newDelayMap[delay.url]![delay.name] = delay.value;
      value = newDelayMap;
    }
  }
}

@Riverpod(keepAlive: true)
class PendingDelayTests extends _$PendingDelayTests
    with AutoDisposeNotifierMixin {
  final Map<String, int> _counts = {};

  @override
  Set<String> build() {
    return const <String>{};
  }

  void acquire(Iterable<String> keys) {
    var added = false;
    for (final key in keys) {
      final count = _counts[key] ?? 0;
      _counts[key] = count + 1;
      added |= count == 0;
    }
    if (added) {
      _publish();
    }
  }

  void release(Iterable<String> keys) {
    var removed = false;
    for (final key in keys) {
      final count = _counts[key];
      if (count == null) {
        continue;
      }
      if (count > 1) {
        _counts[key] = count - 1;
        continue;
      }
      _counts.remove(key);
      removed = true;
    }
    if (removed) {
      _publish();
    }
  }

  void clear() {
    if (_counts.isEmpty) {
      return;
    }
    _counts.clear();
    _publish();
  }

  void _publish() {
    value = Set.unmodifiable(_counts.keys);
  }
}

@Riverpod(keepAlive: true)
class SystemUiOverlayStyleState extends _$SystemUiOverlayStyleState
    with AutoDisposeNotifierMixin {
  @override
  SystemUiOverlayStyle build() {
    return const SystemUiOverlayStyle();
  }
}

@Riverpod(name: 'coreStatusProvider', keepAlive: true)
class _CoreStatus extends _$CoreStatus with AutoDisposeNotifierMixin {
  @override
  CoreStatus build() {
    return CoreStatus.disconnected;
  }
}

@riverpod
class Query extends _$Query with AutoDisposeNotifierMixin {
  @override
  String build(QueryTag tag) {
    return '';
  }
}

@Riverpod(keepAlive: true)
class Loading extends _$Loading with AutoDisposeNotifierMixin {
  DateTime? _start;
  Timer? _timer;

  @override
  bool build(LoadingTag tag) {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return false;
  }

  void start() {
    _timer?.cancel();
    _timer = null;
    _start = DateTime.now();
    value = true;
  }

  Future<void> stop() async {
    if (_start == null) {
      value = false;
      return;
    }
    final startedAt = _start!;
    final elapsed = DateTime.now().difference(_start!).inMilliseconds;
    const minDuration = 1000;
    if (elapsed >= minDuration) {
      value = false;
      return;
    }
    _timer = Timer(Duration(milliseconds: minDuration - elapsed), () {
      if (_start != startedAt) {
        return;
      }
      value = false;
    });
  }
}

@riverpod
class Items extends _$Items with AutoDisposeNotifierMixin {
  @override
  Set<dynamic> build(String key) {
    return {};
  }
}

@riverpod
class Item extends _$Item with AutoDisposeNotifierMixin {
  @override
  dynamic build(String key) {
    return null;
  }
}

@Riverpod(keepAlive: true)
class UpdatingKeys extends _$UpdatingKeys {
  final _operations = <String, Set<int>>{};
  final _scopes = <String, UpdatingScope>{};
  int _operation = 0;

  @override
  Set<String> build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        _discardScope(UpdatingScope.core);
      }
    });
    return const <String>{};
  }

  int start(String key, {UpdatingScope scope = UpdatingScope.local}) {
    final operation = ++_operation;
    _operations.putIfAbsent(key, () => <int>{}).add(operation);
    _scopes[key] = scope;
    if (!state.contains(key)) {
      state = {...state, key};
    }
    return operation;
  }

  void stop(String key, int operation) {
    final operations = _operations[key];
    if (operations == null) {
      return;
    }
    operations.remove(operation);
    if (operations.isNotEmpty) {
      return;
    }
    _discard([key]);
  }

  void stopKeys(Iterable<String> keys) {
    _discard(keys.toList());
  }

  UpdatingScope? scopeOf(String key) => _scopes[key];

  void _discardScope(UpdatingScope scope) {
    _discard(state.where((key) => _scopes[key] == scope).toList());
  }

  void _discard(List<String> keys) {
    if (keys.isEmpty) {
      return;
    }
    for (final key in keys) {
      _operations.remove(key);
      _scopes.remove(key);
    }
    final next = state.where((key) => !keys.contains(key)).toSet();
    if (next.length == state.length) {
      return;
    }
    state = next;
  }
}

@riverpod
bool isUpdating(Ref ref, String name) {
  return ref.watch(updatingKeysProvider).contains(name);
}

@Riverpod(keepAlive: true)
class WindowVisible extends _$WindowVisible with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return true;
  }
}

@Riverpod(keepAlive: true)
class NetworkDetection extends _$NetworkDetection
    with AutoDisposeNotifierMixin {
  static const _timeoutDisplayDelay = Duration(seconds: 2);
  static const _resumeProbeCooldown = Duration(seconds: 45);

  CancelToken? _cancelToken;
  CancelToken? _probeToken;
  CancelToken? _riskToken;
  Timer? _timeoutTimer;
  int _checkVersion = 0;
  int _probeVersion = 0;
  IpInfo? _rawIpInfo;
  DateTime? _lastCheckedAt;
  String? _riskIp;

  IpInfo? get rawIpInfo => _rawIpInfo;

  @override
  NetworkDetectionState build() {
    ref.onDispose(() {
      _resetCheckSession(null);
      _probeToken?.cancel();
      _probeToken = null;
      _riskToken?.cancel();
      _riskToken = null;
      debouncer.cancel(FunctionTag.checkIpRisk);
    });
    return const NetworkDetectionState(isLoading: true, ipInfo: null);
  }

  static String protectedCountryCode([Locale? locale]) {
    final effective = locale ?? PlatformDispatcher.instance.locale;
    return switch (effective.languageCode.toLowerCase()) {
      'ja' => 'JP',
      'ko' => 'KR',
      'ru' => 'RU',
      'fa' => 'IR',
      _ => 'CN',
    };
  }

  IpInfo protectedIpInfo([Locale? locale]) {
    final configuredLocale = getLocaleForString(
      ref.read(appSettingProvider.select((state) => state.locale)),
    );
    return IpInfo(
      ip: '10.0.0.108',
      countryCode: protectedCountryCode(locale ?? configuredLocale),
      country: 'Protected Mode',
      asn: 'AS166188',
    );
  }

  IpInfo? _displayIpInfo(IpInfo? info, {bool? masked}) {
    if (info == null) {
      return null;
    }
    return (masked ?? state.isIpMasked) ? protectedIpInfo() : info;
  }

  void toggleIpPrivacy() {
    final nextMasked = !state.isIpMasked;
    state = state.copyWith(
      isIpMasked: nextMasked,
      ipInfo: _displayIpInfo(_rawIpInfo, masked: nextMasked),
    );
  }

  void manualRefresh() {
    _rawIpInfo = null;
    _lastCheckedAt = null;
    _riskIp = null;
    _riskToken?.cancel();
    _probeToken?.cancel();
    debouncer.cancel(FunctionTag.checkIpRisk);
    state = state.copyWith(
      isLoading: true,
      isRefreshing: false,
      ipInfo: null,
      errorMessage: null,
      riskyIp: null,
      riskLevel: null,
    );
    startCheck(immediate: true, force: true, clearPrevious: true);
  }

  void refreshRiskCheck() {
    _riskIp = null;
    unawaited(_scheduleRiskCheck());
  }

  void startCheck({
    bool immediate = false,
    bool force = false,
    bool clearPrevious = false,
  }) {
    debouncer.call(
      FunctionTag.checkIp,
      () => _checkIp(force: force, clearPrevious: clearPrevious),
      duration: immediate ? Duration.zero : commonDuration,
    );
  }

  Future<void> probeOnResume() async {
    await _probeIfNeeded(isResume: true);
  }

  Future<void> probeForDrift() async {
    await _probeIfNeeded(isResume: false);
  }

  Future<void> _probeIfNeeded({required bool isResume}) async {
    if (!ref.read(initProvider)) {
      return;
    }
    final containsDetection = ref.read(
      dashboardStateProvider.select(
        (state) =>
            state.dashboardWidgets.contains(DashboardWidget.networkDetection),
      ),
    );
    if (!containsDetection) {
      return;
    }
    final current = _rawIpInfo;
    if (current == null) {
      if (!state.isLoading) {
        startCheck(immediate: !isResume);
      }
      return;
    }
    if (isResume &&
        _lastCheckedAt != null &&
        DateTime.now().difference(_lastCheckedAt!) < _resumeProbeCooldown) {
      return;
    }
    if (state.isLoading || state.isRefreshing) {
      return;
    }
    final probeVersion = ++_probeVersion;
    final token = CancelToken();
    _probeToken?.cancel();
    _probeToken = token;
    final res = await request.probePublicIp(cancelToken: token);
    if (!ref.mounted ||
        probeVersion != _probeVersion ||
        !identical(token, _probeToken)) {
      return;
    }
    final probedIp = res.data?.ip;
    if (res.isError || probedIp == null || probedIp.isEmpty) {
      return;
    }
    _lastCheckedAt = DateTime.now();
    if (probedIp == current.ip) {
      return;
    }
    await _checkIp(force: false, clearPrevious: false);
  }

  Future<void> _checkIp({
    bool force = false,
    bool clearPrevious = false,
  }) async {
    final isInit = ref.read(initProvider);
    if (!isInit) {
      return;
    }
    _probeVersion++;
    _probeToken?.cancel();
    _probeToken = null;
    final cancelToken = CancelToken();
    final version = _resetCheckSession(cancelToken);
    commonPrint.log('checkIp start');
    final shouldClear = force || clearPrevious || _rawIpInfo == null;
    if (shouldClear) {
      _rawIpInfo = null;
      state = state.copyWith(
        isLoading: true,
        isRefreshing: false,
        ipInfo: null,
        errorMessage: null,
        riskyIp: null,
        riskLevel: null,
      );
    } else {
      state = state.copyWith(isRefreshing: true, errorMessage: null);
    }

    final res = await request.checkIp(cancelToken: cancelToken);
    commonPrint.log('checkIp res: $res');

    if (!ref.mounted ||
        version != _checkVersion ||
        cancelToken != _cancelToken) {
      return;
    }
    if (res.isError) {
      if (res.message == 'cancelled') {
        return;
      }
      if (_rawIpInfo == null) {
        _delayTimeoutDisplay(version);
      } else {
        state = state.copyWith(isLoading: false, isRefreshing: false);
      }
      return;
    }
    final ipInfo = res.data;
    if (ipInfo == null) {
      if (_rawIpInfo == null) {
        _delayTimeoutDisplay(version);
      } else {
        state = state.copyWith(isLoading: false, isRefreshing: false);
      }
      return;
    }
    _rawIpInfo = ipInfo;
    _lastCheckedAt = DateTime.now();
    state = state.copyWith(
      isLoading: false,
      isRefreshing: false,
      ipInfo: _displayIpInfo(ipInfo),
      errorMessage: null,
    );
    unawaited(_scheduleRiskCheck());
  }

  Future<void> _scheduleRiskCheck() async {
    final ip = _rawIpInfo?.ip;
    final alertEnabled = ref.read(
      appSettingProvider.select((state) => state.ipRiskAlert),
    );
    final containsDetection = ref.read(
      dashboardStateProvider.select(
        (state) =>
            state.dashboardWidgets.contains(DashboardWidget.networkDetection),
      ),
    );
    if (!alertEnabled ||
        !containsDetection ||
        ip == null ||
        classifyIp(ip) != IpCategory.public) {
      _riskIp = null;
      _riskToken?.cancel();
      debouncer.cancel(FunctionTag.checkIpRisk);
      if (state.riskyIp != null || state.riskLevel != null) {
        state = state.copyWith(riskyIp: null, riskLevel: null);
      }
      return;
    }
    if (ip == _riskIp && state.riskLevel != null) {
      return;
    }
    _riskIp = ip;
    _riskToken?.cancel();
    debouncer.cancel(FunctionTag.checkIpRisk);
    final cached = await ipIntelCache.readRisk(ip);
    if (!ref.mounted || ip != _riskIp) {
      return;
    }
    if (cached != null) {
      _applyRisk(ip, cached);
      return;
    }
    debouncer.call(
      FunctionTag.checkIpRisk,
      () => _checkRisk(ip),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _checkRisk(String ip) async {
    if (!ref.mounted ||
        ip != _riskIp ||
        !ref.read(appSettingProvider.select((state) => state.ipRiskAlert))) {
      return;
    }
    final token = CancelToken();
    _riskToken = token;
    final res = await request.queryIpRisk(
      ip,
      cancelToken: token,
      timeout: const Duration(seconds: 5),
    );
    if (!ref.mounted || ip != _riskIp || !identical(token, _riskToken)) {
      return;
    }
    _applyRisk(ip, res.data);
  }

  void _applyRisk(String ip, IpRisk? risk) {
    final level = risk?.level;
    state = state.copyWith(
      riskyIp: level != null && level != IpRiskLevel.low ? ip : null,
      riskLevel: level,
    );
  }

  int _resetCheckSession(CancelToken? cancelToken) {
    _cancelTimeoutTimer();
    final version = ++_checkVersion;
    final previousCancelToken = _cancelToken;
    _cancelToken = cancelToken;
    previousCancelToken?.cancel();
    return version;
  }

  void _delayTimeoutDisplay(int version) {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(_timeoutDisplayDelay, () {
      _timeoutTimer = null;
      if (!ref.mounted || version != _checkVersion || _rawIpInfo != null) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        ipInfo: null,
        errorMessage: currentAppLocalizations.timeout,
      );
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}

@Riverpod(keepAlive: true)
class CurrentSSID extends _$CurrentSSID with AutoDisposeNotifierMixin {
  @override
  String? build() {
    return null;
  }
}

@Riverpod(keepAlive: true)
class BatteryOptimizationDisable extends _$BatteryOptimizationDisable
    with AutoDisposeNotifierMixin {
  @override
  bool build() {
    return false;
  }
}

@Riverpod(keepAlive: true)
class LocationPermissions extends _$LocationPermissions
    with AutoDisposeNotifierMixin {
  @override
  WifiSsidPermission build() {
    return WifiSsidPermission.denied;
  }
}

List<Override> buildAppStateOverrides(AppState appState) {
  return [
    initProvider.overrideWithBuild((_, _) => appState.isInit),
    currentPageLabelProvider.overrideWithBuild((_, _) => appState.pageLabel),
    packagesProvider.overrideWithBuild((_, _) => appState.packages),
    sortNumProvider.overrideWithBuild((_, _) => appState.sortNum),
    viewSizeProvider.overrideWithBuild((_, _) => appState.viewSize),
    sideWidthProvider.overrideWithBuild((_, _) => appState.sideWidth),
    delayDataSourceProvider.overrideWithBuild((_, _) => appState.delayMap),
    groupsProvider.overrideWithBuild((_, _) => appState.groups),
    checkIpNumProvider.overrideWithBuild((_, _) => appState.checkIpNum),
    systemBrightnessProvider.overrideWithBuild((_, _) => appState.brightness),
    runTimeProvider.overrideWithBuild((_, _) => appState.runTime),
    providersProvider.overrideWithBuild((_, _) => appState.providers),
    localIpProvider.overrideWithBuild((_, _) => appState.localIp),
    requestsProvider.overrideWithBuild((_, _) => appState.requests),
    versionProvider.overrideWithBuild((_, _) => appState.version),
    logsProvider.overrideWithBuild((_, _) => appState.logs),
    trafficsProvider.overrideWithBuild((_, _) => appState.traffics),
    totalTrafficProvider.overrideWithBuild((_, _) => appState.totalTraffic),
    authorizedTunEnableProvider.overrideWithBuild(
      (_, _) => appState.authorizedTunEnable,
    ),
    systemUiOverlayStyleStateProvider.overrideWithBuild(
      (_, _) => appState.systemUiOverlayStyle,
    ),
    coreStatusProvider.overrideWithBuild((_, _) => appState.coreStatus),
  ];
}
