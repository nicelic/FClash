import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class IpIntelCache {
  static const int maxEntries = 64;
  static const Duration detailTtl = Duration(hours: 24);
  static const Duration riskTtl = Duration(hours: 12);

  final SerialTaskScheduler _scheduler = SerialTaskScheduler();
  final Future<Directory?> Function()? _directoryResolver;
  final DateTime Function() _now;

  IpIntelCache({
    @visibleForTesting Future<Directory?> Function()? directoryResolver,
    @visibleForTesting DateTime Function()? now,
  }) : _directoryResolver = directoryResolver,
       _now = now ?? DateTime.now;

  Future<File?> _cacheFile() async {
    try {
      if (_directoryResolver != null) {
        final dir = await _directoryResolver();
        return dir == null
            ? null
            : File(p.join(dir.path, 'ip_intel_cache.json'));
      }
      if (!AppPath.isInitialized) {
        return null;
      }
      final dir = await appPath.cacheDir.future.timeout(
        const Duration(milliseconds: 100),
      );
      return File(p.join(dir.path, 'ip_intel_cache.json'));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadStore(File file) async {
    try {
      if (!await file.exists()) {
        return {};
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return {};
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return {};
      }
      final nowMs = _now().millisecondsSinceEpoch;
      final store = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        final key = entry.key?.toString();
        final value = entry.value;
        if (key == null || value is! Map) {
          continue;
        }
        final expiresAt = value['expiresAt'];
        if (expiresAt is! int || expiresAt <= nowMs) {
          continue;
        }
        final payload = value['data'];
        if (payload is Map) {
          store[key] = {
            'expiresAt': expiresAt,
            'updatedAt': value['updatedAt'] is int ? value['updatedAt'] : 0,
            'data': Map<String, dynamic>.from(payload),
          };
        }
      }
      return store;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveStore(
    File file,
    Map<String, Map<String, dynamic>> store,
  ) async {
    try {
      if (store.length > maxEntries) {
        final sorted = store.entries.toList()
          ..sort((a, b) {
            final aTime = a.value['updatedAt'] as int? ?? 0;
            final bTime = b.value['updatedAt'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });
        store = {
          for (final entry in sorted.take(maxEntries)) entry.key: entry.value,
        };
      }
      await file.safeWriteAsString(json.encode(store));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> readRaw(String key) {
    return _scheduler.run(() async {
      final file = await _cacheFile();
      if (file == null) {
        return null;
      }
      final store = await _loadStore(file);
      final entry = store[key];
      if (entry == null) {
        return null;
      }
      final data = entry['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  Future<void> writeRaw(
    String key,
    Map<String, dynamic> data, {
    required Duration ttl,
  }) {
    return _scheduler.run(() async {
      final file = await _cacheFile();
      if (file == null) {
        return;
      }
      final store = await _loadStore(file);
      final nowMs = _now().millisecondsSinceEpoch;
      store[key] = {
        'expiresAt': nowMs + ttl.inMilliseconds,
        'updatedAt': nowMs,
        'data': data,
      };
      await _saveStore(file, store);
    });
  }

  String detailKey(String ip) {
    final isZh = Intl.getCurrentLocale().toLowerCase().startsWith('zh');
    return 'detail_${ip}_${isZh ? 'zh' : 'en'}';
  }

  Future<IpInfo?> readDetail(String ip) async {
    try {
      final data = await readRaw(detailKey(ip));
      return data == null ? null : IpInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDetail(IpInfo info) async {
    try {
      await writeRaw(detailKey(info.ip), info.toJson(), ttl: detailTtl);
    } catch (_) {}
  }

  Future<IpRisk?> readRisk(String ip) async {
    try {
      final data = await readRaw('risk_$ip');
      return data == null ? null : IpRisk.fromJson(data).normalized;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeRisk(IpRisk risk) async {
    try {
      await writeRaw('risk_${risk.ip}', risk.toJson(), ttl: riskTtl);
    } catch (_) {}
  }
}

final ipIntelCache = IpIntelCache();
