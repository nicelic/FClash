import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

List<TrackerInfo> sortConnections(
  List<TrackerInfo> trackerInfos,
  ConnectionSortMode mode,
) {
  if (trackerInfos.length <= 1) {
    return List<TrackerInfo>.of(trackerInfos, growable: false);
  }
  final sorted = List<TrackerInfo>.of(trackerInfos, growable: false);
  sorted.sort((a, b) => compareConnections(a, b, mode));
  return sorted;
}

int compareConnections(
  TrackerInfo a,
  TrackerInfo b,
  ConnectionSortMode mode,
) {
  final desc = mode.descending;
  switch (mode.category) {
    case ConnectionSortCategory.speed:
      final aSpeed = (a.uploadSpeed ?? 0) + (a.downloadSpeed ?? 0);
      final bSpeed = (b.uploadSpeed ?? 0) + (b.downloadSpeed ?? 0);
      final speedCmp = desc
          ? bSpeed.compareTo(aSpeed)
          : aSpeed.compareTo(bSpeed);
      if (speedCmp != 0) {
        return speedCmp;
      }
      final trafficCmp = _compareTraffic(a, b, descending: desc);
      if (trafficCmp != 0) {
        return trafficCmp;
      }
      return _compareStartAndId(a, b, descending: true);
    case ConnectionSortCategory.traffic:
      final trafficCmp = _compareTraffic(a, b, descending: desc);
      if (trafficCmp != 0) {
        return trafficCmp;
      }
      return _compareStartAndId(a, b, descending: true);
    case ConnectionSortCategory.time:
    case ConnectionSortCategory.defaultTime:
      return _compareStartAndId(a, b, descending: desc);
  }
}

int _compareTraffic(
  TrackerInfo a,
  TrackerInfo b, {
  required bool descending,
}) {
  final aTraffic = a.upload + a.download;
  final bTraffic = b.upload + b.download;
  return descending
      ? bTraffic.compareTo(aTraffic)
      : aTraffic.compareTo(bTraffic);
}

int _compareStartAndId(
  TrackerInfo a,
  TrackerInfo b, {
  required bool descending,
}) {
  final aStart = a.start.microsecondsSinceEpoch;
  final bStart = b.start.microsecondsSinceEpoch;
  final startCmp = descending
      ? bStart.compareTo(aStart)
      : aStart.compareTo(bStart);
  if (startCmp != 0) {
    return startCmp;
  }
  return a.id.compareTo(b.id);
}
