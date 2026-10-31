import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
import 'retry_interceptor.dart';

/// Builds and owns the configured [Dio] instances.
///
/// Two clients exist deliberately:
///   - [dio] is what repositories use. It carries auth, retry and logging.
///   - [_bareClient] has no auth interceptor and is used for token refresh and
///     for replaying a request after a refresh. Routing those through [dio]
///     would recurse into the interceptor that triggered them.
class DioClient {
  DioClient({
    required TokenStore tokenStore,
    required Future<void> Function() onSessionExpired,
    String? baseUrl,
  }) {
    final resolvedBaseUrl = baseUrl ?? AppConfig.apiBaseUrl;

    _bareClient = Dio(_baseOptions(resolvedBaseUrl));
    dio = Dio(_baseOptions(resolvedBaseUrl));

    dio.interceptors.addAll([
      AuthInterceptor(
        tokenStore: tokenStore,
        retryClient: _bareClient,
        onSessionExpired: onSessionExpired,
      ),
      RetryInterceptor(dio: _bareClient),
      if (AppConfig.debugLogging) _LogInterceptor(),
    ]);

    // The bare client still benefits from retry on the refresh call itself.
    _bareClient.interceptors.addAll([
      RetryInterceptor(dio: Dio(_baseOptions(resolvedBaseUrl))),
      if (AppConfig.debugLogging) _LogInterceptor(prefix: 'bare'),
    ]);
  }

  late final Dio dio;
  late final Dio _bareClient;

  static BaseOptions _baseOptions(String baseUrl) => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.sendTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        // We inspect error bodies ourselves, so let every status through to the
        // interceptors rather than having Dio throw before they see it.
        validateStatus: (status) => status != null && status < 400,
        headers: {'Accept': 'application/json'},
      );
}

/// Compact request/response logger. Redacts credentials, because a stack trace
/// pasted into a bug report should not contain somebody's password or token.
class _LogInterceptor extends Interceptor {
  _LogInterceptor({this.prefix = 'api'});

  final String prefix;

  static const _sensitiveKeys = {
    'password',
    'confirmPassword',
    'currentPassword',
    'newPassword',
    'otp',
    'accessToken',
    'refreshToken',
    'verificationToken',
    'fcmToken',
  };

  Object? _redact(Object? value) {
    if (value is Map) {
      return value.map((key, inner) {
        if (_sensitiveKeys.contains(key)) return MapEntry(key, '***');
        return MapEntry(key, _redact(inner));
      });
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // ignore: avoid_print
    print('[$prefix] --> ${options.method} ${options.path} ${_redact(options.data) ?? ''}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    // ignore: avoid_print
    print(
      '[$prefix] <-- ${response.statusCode} '
      '${response.requestOptions.method} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final code = err.response?.data is Map ? (err.response!.data as Map)['code'] : err.type.name;
    // ignore: avoid_print
    print(
      '[$prefix] <-- ERROR ${err.response?.statusCode ?? '-'} '
      '${err.requestOptions.method} ${err.requestOptions.path} ($code)',
    );
    handler.next(err);
  }
}
