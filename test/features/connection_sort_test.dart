import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/connection_sort.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _tracker(
  String id, {
  int upload = 0,
  int download = 0,
  int? uploadSpeed,
  int? downloadSpeed,
  DateTime? start,
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    uploadSpeed: uploadSpeed,
    downloadSpeed: downloadSpeed,
    start: start ?? DateTime.utc(2026),
    metadata: const Metadata(
      network: 'tcp',
      host: 'example.com',
      destinationPort: '443',
    ),
    chains: const ['Proxy'],
    rule: 'MATCH',
    rulePayload: '',
  );
}

void main() {
  group('ConnectionSortMode.selectCategory', () {
    test('defaults to descending when switching category and toggles on repeat', () {
      var mode = ConnectionSortMode.defaultTimeDesc;

      mode = mode.selectCategory(ConnectionSortCategory.speed);
      expect(mode, ConnectionSortMode.speedDesc);

      mode = mode.selectCategory(ConnectionSortCategory.speed);
      expect(mode, ConnectionSortMode.speedAsc);

      mode = mode.selectCategory(ConnectionSortCategory.speed);
      expect(mode, ConnectionSortMode.speedDesc);

      mode = mode.selectCategory(ConnectionSortCategory.traffic);
      expect(mode, ConnectionSortMode.trafficDesc);

      mode = mode.selectCategory(ConnectionSortCategory.traffic);
      expect(mode, ConnectionSortMode.trafficAsc);

      mode = mode.selectCategory(ConnectionSortCategory.time);
      expect(mode, ConnectionSortMode.timeDesc);

      mode = mode.selectCategory(ConnectionSortCategory.time);
      expect(mode, ConnectionSortMode.timeAsc);

      mode = mode.selectCategory(ConnectionSortCategory.defaultTime);
      expect(mode, ConnectionSortMode.defaultTimeDesc);

      mode = mode.selectCategory(ConnectionSortCategory.defaultTime);
      expect(mode, ConnectionSortMode.defaultTimeAsc);
    });
  });

  group('sortConnections', () {
    test('orders by creation time for defaultTime and time modes', () {
      final items = [
        _tracker('b', start: DateTime.utc(2026, 1, 1)),
        _tracker('a', start: DateTime.utc(2026, 1, 3)),
        _tracker('c', start: DateTime.utc(2026, 1, 2)),
      ];

      expect(
        sortConnections(items, ConnectionSortMode.defaultTimeDesc).map((e) => e.id),
        ['a', 'c', 'b'],
      );
      expect(
        sortConnections(items, ConnectionSortMode.defaultTimeAsc).map((e) => e.id),
        ['b', 'c', 'a'],
      );
      expect(
        sortConnections(items, ConnectionSortMode.timeDesc).map((e) => e.id),
        ['a', 'c', 'b'],
      );
      expect(
        sortConnections(items, ConnectionSortMode.timeAsc).map((e) => e.id),
        ['b', 'c', 'a'],
      );
    });

    test('orders by total speed with deterministic tie-breakers', () {
      final items = [
        _tracker(
          'zero-low-traffic',
          upload: 100,
          download: 100,
          uploadSpeed: 0,
          downloadSpeed: 0,
        ),
        _tracker(
          'fast',
          upload: 10,
          download: 10,
          uploadSpeed: 200,
          downloadSpeed: 800,
        ),
        _tracker(
          'zero-high-traffic',
          upload: 5000,
          download: 5000,
          uploadSpeed: 0,
          downloadSpeed: 0,
        ),
        _tracker(
          'medium',
          upload: 1000,
          download: 1000,
          uploadSpeed: 100,
          downloadSpeed: 100,
        ),
      ];

      expect(
        sortConnections(items, ConnectionSortMode.speedDesc).map((e) => e.id),
        ['fast', 'medium', 'zero-high-traffic', 'zero-low-traffic'],
      );
      expect(
        sortConnections(items, ConnectionSortMode.speedAsc).map((e) => e.id),
        ['zero-low-traffic', 'zero-high-traffic', 'medium', 'fast'],
      );
    });

    test('orders by total traffic in both directions', () {
      final items = [
        _tracker('small', upload: 50, download: 50),
        _tracker('large', upload: 500, download: 700),
        _tracker('mid', upload: 200, download: 300),
      ];

      expect(
        sortConnections(items, ConnectionSortMode.trafficDesc).map((e) => e.id),
        ['large', 'mid', 'small'],
      );
      expect(
        sortConnections(items, ConnectionSortMode.trafficAsc).map((e) => e.id),
        ['small', 'mid', 'large'],
      );
    });
  });
}
