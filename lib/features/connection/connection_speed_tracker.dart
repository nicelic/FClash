import 'package:fl_clash/models/models.dart';

typedef _ConnectionTotals = ({int upload, int download});

class ConnectionSpeedTracker {
  static const int minSampleGapMs = 200;
  static const int maxSampleGapMs = 5000;
  static const _ConnectionTotals _zeroTotals = (upload: 0, download: 0);

  final Stopwatch? _stopwatch;
  final int Function()? _nowMsProvider;

  Map<String, _ConnectionTotals> _previousTotals = const {};
  Map<String, _ConnectionTotals> _lastSpeeds = const {};
  int? _previousTimestampMs;

  ConnectionSpeedTracker({int Function()? nowMs})
    : _nowMsProvider = nowMs,
      _stopwatch = nowMs == null ? (Stopwatch()..start()) : null;

  int get _nowMs => _nowMsProvider?.call() ?? _stopwatch!.elapsedMilliseconds;

  void reset() {
    _previousTotals = const {};
    _lastSpeeds = const {};
    _previousTimestampMs = null;
  }

  List<TrackerInfo> apply(List<TrackerInfo> trackerInfos) {
    if (trackerInfos.isEmpty) {
      reset();
      return trackerInfos;
    }

    final nowMs = _nowMs;
    final prevTs = _previousTimestampMs;
    final deltaMs = prevTs == null ? 0 : nowMs - prevTs;

    // Keep cached rates across rapid manual refreshes so tiny intervals do
    // not divide small deltas into fake spikes.
    if (prevTs != null && deltaMs >= 0 && deltaMs < minSampleGapMs) {
      return List<TrackerInfo>.generate(trackerInfos.length, (index) {
        final info = trackerInfos[index];
        return _withSpeed(info, _lastSpeeds[info.id] ?? _zeroTotals);
      }, growable: false);
    }

    final canComputeRate =
        prevTs != null && deltaMs >= minSampleGapMs && deltaMs <= maxSampleGapMs;
    final nextTotals = <String, _ConnectionTotals>{};
    final nextSpeeds = <String, _ConnectionTotals>{};

    final result = List<TrackerInfo>.generate(trackerInfos.length, (index) {
      final info = trackerInfos[index];
      nextTotals[info.id] = (upload: info.upload, download: info.download);
      var upSpeed = 0;
      var downSpeed = 0;
      if (canComputeRate) {
        final prev = _previousTotals[info.id];
        if (prev != null) {
          final upDelta = info.upload - prev.upload;
          final downDelta = info.download - prev.download;
          if (upDelta > 0) {
            upSpeed = (upDelta * 1000 + deltaMs ~/ 2) ~/ deltaMs;
          }
          if (downDelta > 0) {
            downSpeed = (downDelta * 1000 + deltaMs ~/ 2) ~/ deltaMs;
          }
        }
      }
      final speed = (upload: upSpeed, download: downSpeed);
      nextSpeeds[info.id] = speed;
      return _withSpeed(info, speed);
    }, growable: false);

    _previousTotals = nextTotals;
    _lastSpeeds = nextSpeeds;
    _previousTimestampMs = nowMs;
    return result;
  }

  TrackerInfo _withSpeed(TrackerInfo info, _ConnectionTotals speed) {
    if (info.uploadSpeed == speed.upload &&
        info.downloadSpeed == speed.download) {
      return info;
    }
    return info.copyWith(
      uploadSpeed: speed.upload,
      downloadSpeed: speed.download,
    );
  }
}
