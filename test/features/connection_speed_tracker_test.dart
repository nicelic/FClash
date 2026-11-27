import 'package:fl_clash/features/connection/connection_speed_tracker.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _tracker(
  String id, {
  int upload = 0,
  int download = 0,
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    start: DateTime(2026),
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
  test('computes per-connection speeds from byte deltas over elapsed ms', () {
    var nowMs = 1000;
    final tracker = ConnectionSpeedTracker(nowMs: () => nowMs);

    final first = tracker.apply([
      _tracker('a', upload: 29150413, download: 6815744),
    ]);
    expect(first.single.uploadSpeed, 0);
    expect(first.single.downloadSpeed, 0);

    nowMs = 2000;
    final second = tracker.apply([
      _tracker(
        'a',
        upload: 29150413 + 128 * 1024,
        download: 6815744 + 2516582,
      ),
      _tracker('b', upload: 1024, download: 2048),
    ]);
    expect(second[0].uploadSpeed, 128 * 1024);
    expect(second[0].downloadSpeed, 2516582);
    expect(second[1].uploadSpeed, 0);
    expect(second[1].downloadSpeed, 0);
  });

  test('preserves cached speeds across sub-interval refreshes', () {
    var nowMs = 1000;
    final tracker = ConnectionSpeedTracker(nowMs: () => nowMs);

    tracker.apply([_tracker('a', upload: 1000, download: 2000)]);
    nowMs = 2000;
    final sampled = tracker.apply([
      _tracker('a', upload: 3000, download: 6000),
    ]);
    expect(sampled.single.uploadSpeed, 2000);
    expect(sampled.single.downloadSpeed, 4000);

    nowMs = 2050;
    final manual = tracker.apply([
      _tracker('a', upload: 3050, download: 6100),
    ]);
    expect(manual.single.uploadSpeed, 2000);
    expect(manual.single.downloadSpeed, 4000);

    nowMs = 3000;
    final next = tracker.apply([
      _tracker('a', upload: 5000, download: 10000),
    ]);
    expect(next.single.uploadSpeed, 2000);
    expect(next.single.downloadSpeed, 4000);
  });

  test('resets baseline after long gap or reset call and drops closed ids', () {
    var nowMs = 1000;
    final tracker = ConnectionSpeedTracker(nowMs: () => nowMs);

    tracker.apply([
      _tracker('a', upload: 1000, download: 1000),
      _tracker('b', upload: 500, download: 500),
    ]);

    nowMs = 8000;
    final resumed = tracker.apply([
      _tracker('a', upload: 500000, download: 900000),
    ]);
    expect(resumed.single.uploadSpeed, 0);
    expect(resumed.single.downloadSpeed, 0);

    nowMs = 9000;
    final steady = tracker.apply([
      _tracker('a', upload: 501024, download: 902048),
      _tracker('b', upload: 5000, download: 5000),
    ]);
    expect(steady[0].uploadSpeed, 1024);
    expect(steady[0].downloadSpeed, 2048);
    expect(steady[1].uploadSpeed, 0);
    expect(steady[1].downloadSpeed, 0);

    tracker.reset();
    nowMs = 10000;
    final afterReset = tracker.apply([
      _tracker('a', upload: 502048, download: 904096),
    ]);
    expect(afterReset.single.uploadSpeed, 0);
    expect(afterReset.single.downloadSpeed, 0);
  });

  test('clamps negative counter deltas to zero', () {
    var nowMs = 1000;
    final tracker = ConnectionSpeedTracker(nowMs: () => nowMs);

    tracker.apply([_tracker('a', upload: 5000, download: 8000)]);
    nowMs = 2000;
    final clamped = tracker.apply([_tracker('a', upload: 100, download: 200)]);
    expect(clamped.single.uploadSpeed, 0);
    expect(clamped.single.downloadSpeed, 0);
  });
}
