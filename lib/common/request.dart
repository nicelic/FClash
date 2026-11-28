import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:intl/intl.dart';

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return FlClashHttpOverrides.findProxyForReader(read, uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    try {
      return await _clashDio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      if (!hasUpdate) return null;
      return data;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  ({Dio dio, bool shouldClose}) _createIpDio(Duration timeout) {
    final headers = <String, dynamic>{
      'User-Agent': browserUa,
      'Connection': 'close',
    };
    final baseOptions = BaseOptions(
      headers: headers,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
    );
    if (dio.httpClientAdapter is! IOHttpClientAdapter) {
      final testDio = Dio(baseOptions)..httpClientAdapter = dio.httpClientAdapter;
      return (dio: testDio, shouldClose: false);
    }
    final ephemeral = Dio(baseOptions);
    ephemeral.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.idleTimeout = Duration.zero;
        client.connectionTimeout = timeout;
        client.findProxy = (uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return FlClashHttpOverrides.findProxyForReader(read, uri);
        };
        final read = _read;
        if (read != null) {
          client.badCertificateCallback = (cert, host, port) =>
              FlClashHttpOverrides.allowBadCertificateForReader(
                read,
                cert,
                host,
                port,
              );
        }
        return client;
      },
    );
    return (dio: ephemeral, shouldClose: true);
  }

  Map<String, IpInfo Function(Map<String, dynamic>)> get _ipInfoSources {
    final isZh = Intl.getCurrentLocale().toLowerCase().startsWith('zh');
    return {
      'https://ipwho.is': IpInfo.fromIpWhoIsJson,
      'https://get.geojs.io/v1/ip/geo.json': IpInfo.fromGeoJsJson,
      'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
      'https://ident.me/json': IpInfo.fromIdentMeJson,
      isZh ? 'http://ip-api.com/json?lang=zh-CN' : 'http://ip-api.com/json':
          IpInfo.fromIpAPIJson,
      'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
      'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
    };
  }

  Future<Result<IpInfo?>> checkIp({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sources = _ipInfoSources;
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final client = _createIpDio(timeout);
    try {
      final futures = sources.entries.map((source) async {
        final Completer<Result<IpInfo?>> completer = Completer();
        void handleFailRes() {
          if (!completer.isCompleted && failureCount == sources.length) {
            completer.complete(Result.success(null));
          }
        }

        final future = client.dio
            .get<Map<String, dynamic>>(
              source.key,
              cancelToken: token,
              options: Options(responseType: ResponseType.json),
            )
            .timeout(timeout);
        unawaited(
          future
              .then((res) {
                if (res.statusCode == HttpStatus.ok && res.data != null) {
                  final parsed = source.value(res.data!);
                  if (!completer.isCompleted) {
                    completer.complete(Result.success(parsed));
                  }
                  return;
                }
                commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
                failureCount++;
                handleFailRes();
              })
              .catchError((e) {
                failureCount++;
                if (e is DioException && e.type == DioExceptionType.cancel) {
                  if (!completer.isCompleted) {
                    completer.complete(Result.error('cancelled'));
                  }
                  return;
                }
                commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
                handleFailRes();
              }),
        );
        return completer.future;
      });
      final res = await Future.any(futures);
      token.cancel();
      final info = res.data;
      if (info != null) {
        if (info.hasDetails) {
          unawaited(ipIntelCache.writeDetail(info));
        } else {
          final cached = await ipIntelCache.readDetail(info.ip);
          if (cached != null) {
            return Result.success(info.merge(cached));
          }
        }
      }
      return res;
    } finally {
      if (client.shouldClose) {
        client.dio.close(force: true);
      }
    }
  }

  Future<Result<IpInfo?>> probePublicIp({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final token = cancelToken ?? CancelToken();
    final client = _createIpDio(timeout);
    try {
      try {
        final traceRes = await client.dio
            .get<String>(
              'https://1.1.1.1/cdn-cgi/trace',
              cancelToken: token,
              options: Options(responseType: ResponseType.plain),
            )
            .timeout(timeout);
        if (traceRes.statusCode == HttpStatus.ok && traceRes.data != null) {
          return Result.success(IpInfo.fromCloudflareTrace(traceRes.data!));
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || token.isCancelled) {
          return Result.error('cancelled');
        }
      } catch (_) {}

      if (token.isCancelled) {
        return Result.error('cancelled');
      }
      try {
        final ipifyRes = await client.dio
            .get<Map<String, dynamic>>(
              'https://api.ipify.org?format=json',
              cancelToken: token,
              options: Options(responseType: ResponseType.json),
            )
            .timeout(timeout);
        final ip = ipifyRes.data?['ip']?.toString().trim();
        if (ipifyRes.statusCode == HttpStatus.ok &&
            ip != null &&
            ip.isNotEmpty) {
          return Result.success(IpInfo(ip: ip, countryCode: ''));
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || token.isCancelled) {
          return Result.error('cancelled');
        }
      } catch (_) {}

      return Result.success(null);
    } finally {
      if (client.shouldClose) {
        client.dio.close(force: true);
      }
    }
  }

  Future<Result<IpInfo?>> queryIpDetail(
    String ip, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final cached = await ipIntelCache.readDetail(ip);
    if (cached != null && cached.hasDetails) {
      return Result.success(cached);
    }
    final isZh = Intl.getCurrentLocale().toLowerCase().startsWith('zh');
    final encodedIp = Uri.encodeComponent(ip);
    final endpoints = <(String url, IpInfo Function(Map<String, dynamic>) parser)>[
      (
        isZh
            ? 'http://ip-api.com/json/$encodedIp?lang=zh-CN'
            : 'http://ip-api.com/json/$encodedIp',
        IpInfo.fromIpAPIJson,
      ),
      ('https://ipwho.is/$encodedIp', IpInfo.fromIpWhoIsJson),
    ];
    final client = _createIpDio(timeout);
    try {
      String? lastError;
      for (final endpoint in endpoints) {
        if (cancelToken?.isCancelled ?? false) {
          return Result.error('cancelled');
        }
        try {
          final res = await client.dio
              .get<Map<String, dynamic>>(
                endpoint.$1,
                cancelToken: cancelToken,
                options: Options(responseType: ResponseType.json),
              )
              .timeout(timeout);
          if (res.statusCode == HttpStatus.ok && res.data != null) {
            final parsed = endpoint.$2(res.data!);
            await ipIntelCache.writeDetail(parsed);
            return Result.success(parsed);
          }
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            return Result.error('cancelled');
          }
          lastError = e.toString();
        } catch (e) {
          lastError = e.toString();
        }
      }
      return Result.error(lastError ?? 'query failed');
    } finally {
      if (client.shouldClose) {
        client.dio.close(force: true);
      }
    }
  }

  Future<Result<IpRisk?>> queryIpRisk(
    String ip, {
    bool force = false,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!force) {
      final cached = await ipIntelCache.readRisk(ip);
      if (cached != null) {
        return Result.success(cached);
      }
    }
    final client = _createIpDio(timeout);
    try {
      final res = await client.dio
          .get<List<int>>(
            'https://scamalytics.com/ip/${Uri.encodeComponent(ip)}',
            cancelToken: cancelToken,
            options: Options(responseType: ResponseType.bytes),
          )
          .timeout(timeout);
      final data = res.data;
      if (res.statusCode != HttpStatus.ok || data == null) {
        return Result.error('query failed');
      }
      final risk = await Isolate.run(() => parseScamalyticsBytes(ip, data));
      if (risk == null) {
        return Result.error('parse failed');
      }
      await ipIntelCache.writeRisk(risk);
      return Result.success(risk);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return Result.error('cancelled');
      }
      return Result.error(e.toString());
    } catch (e) {
      return Result.error(e.toString());
    } finally {
      if (client.shouldClose) {
        client.dio.close(force: true);
      }
    }
  }
}

final request = Request();

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
