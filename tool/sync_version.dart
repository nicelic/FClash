import 'dart:io';

void main(List<String> args) {
  final envTag =
      Platform.environment['TAG_NAME'] ??
      Platform.environment['GITHUB_REF_NAME'] ??
      '';
  final tag = args.isNotEmpty ? args.first : envTag;
  final match = RegExp(r'^v(\d+\.\d+\.\d+)').firstMatch(tag.trim());
  if (match == null) {
    return;
  }

  final targetVersion = match.group(1)!;
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final updated = syncPubspecVersion(
    content,
    targetVersion,
    now: DateTime.now().toUtc(),
  );
  if (updated != content) {
    pubspecFile.writeAsStringSync(updated);
    stdout.writeln('Synced pubspec.yaml version to $targetVersion');
  }
}

String syncPubspecVersion(
  String pubspecContent,
  String targetVersion, {
  DateTime? now,
}) {
  final linePattern = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$',
    multiLine: true,
  );
  final match = linePattern.firstMatch(pubspecContent);
  if (match == null) {
    throw const FormatException('Missing valid version line in pubspec.yaml');
  }

  final currentVersion = match.group(1)!;
  final existingBuild = int.tryParse(match.group(2) ?? '');
  if (currentVersion == targetVersion && existingBuild != null) {
    return pubspecContent;
  }

  final utcNow = (now ?? DateTime.now().toUtc()).toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final year = utcNow.year.toString().padLeft(4, '0');
  final ymd = '$year${two(utcNow.month)}${two(utcNow.day)}';
  final todayBase = int.parse('${ymd}01');
  final nextBuild = existingBuild == null
      ? todayBase
      : (existingBuild >= todayBase ? existingBuild + 1 : todayBase);

  return pubspecContent.replaceRange(
    match.start,
    match.end,
    'version: $targetVersion+$nextBuild',
  );
}
