import 'package:test/test.dart';

import '../../tool/sync_version.dart';

void main() {
  group('syncPubspecVersion', () {
    test('updates semantic version and resets build number to today', () {
      const input = 'name: fl_clash\nversion: 0.8.98+2026091401\n';
      final result = syncPubspecVersion(
        input,
        '0.8.99',
        now: DateTime.utc(2026, 11, 27),
      );

      expect(result, 'name: fl_clash\nversion: 0.8.99+2026112701\n');
    });

    test('increments build number when existing build matches today', () {
      const input = 'name: fl_clash\nversion: 0.8.98+2026112701\n';
      final result = syncPubspecVersion(
        input,
        '0.8.99',
        now: DateTime.utc(2026, 11, 27),
      );

      expect(result, 'name: fl_clash\nversion: 0.8.99+2026112702\n');
    });

    test('leaves pubspec untouched when semantic version already matches', () {
      const input = 'name: fl_clash\nversion: 0.8.99+2026112703\n';
      final result = syncPubspecVersion(
        input,
        '0.8.99',
        now: DateTime.utc(2026, 11, 27),
      );

      expect(result, input);
    });
  });
}
