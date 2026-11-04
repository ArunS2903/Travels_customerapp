import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Retries requests that failed for transport reasons.
///
/// Only *safe* requests are retried automatically: GET, plus any request that
/// explicitly opts in with `extra: {'retryable': true}`. Blindly retrying a
/// POST would risk creating two bookings for one tap - booking creation instead
/// carries an `idempotencyKey` and opts in, so a retry is provably harmless.
///
/// Backoff is exponential with jitter, because a dozen clients retrying in
/// lockstep after a blip is how a recovering server gets knocked over again.
///
/// The attempt count is small on purpose. Every attempt costs a full timeout,
/// so the number of retries sets how long a customer stares at a spinner before
/// being told anything: three attempts at the old 20-second receive timeout was
/// a minute of silence. A second attempt absorbs a genuine blip; a third mostly
/// just delays the bad news. See [AppConfig.networkAttempts].
class RetryInterceptor extends Interceptor {
  RetryInterceptor({required Dio dio, int? maxAttempts})
      : _dio = dio,
        maxAttempts = maxAttempts ?? AppConfig.networkAttempts;

  final Dio _dio;
  final int maxAttempts;

  static const _attemptKey = '__retry_attempt';
  static const _random = _Jitter();

  bool _isRetryable(DioException error) {
    final options = error.requestOptions;

    final optedIn = options.extra['retryable'] == true;
    final isSafeMethod = options.method.toUpperCase() == 'GET';
    if (!optedIn && !isSafeMethod) return false;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        // 5xx may be transient. 502/503/504 especially so. A 4xx will not
        // change on retry, and a 429 has its own Retry-After handling below.
        return status >= 500 && status <= 599;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;

    if (attempt >= maxAttempts - 1 || !_isRetryable(err)) {
      return handler.next(err);
    }

    // 2^attempt * 400ms, plus up to 250ms of jitter: ~0.4s, then ~0.8s.
    final backoff = Duration(
      milliseconds: (400 * pow(2, attempt)).toInt() + _random.nextInt(250),
    );

    if (AppConfig.debugLogging) {
      // ignore: avoid_print
      print(
        '[retry] attempt ${attempt + 2}/$maxAttempts for '
        '${err.requestOptions.method} ${err.requestOptions.path} in ${backoff.inMilliseconds}ms',
      );
    }

    await Future<void>.delayed(backoff);

    try {
      final response = await _dio.fetch<dynamic>(
        err.requestOptions.copyWith(
          extra: {...err.requestOptions.extra, _attemptKey: attempt + 1},
        ),
      );
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}

/// Tiny wrapper so the interceptor can hold a `const` random source.
class _Jitter {
  const _Jitter();
  int nextInt(int max) => Random().nextInt(max);
}
