import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../constants/api_endpoints.dart';
import '../storage/token_store.dart';

/// Attaches the access token and transparently refreshes it when it expires.
///
/// The hard part is concurrency: when a screen fires three requests at once and
/// the token has just expired, all three come back 401. Without coordination
/// each would start its own refresh, and because the backend rotates refresh
/// tokens one-use, the second and third would present an already-revoked token
/// and trip the reuse alarm - signing the customer out for being online.
///
/// So the first 401 starts a refresh and stores the in-flight [Future] in
/// [_refreshOperation]; the others await the same future and then retry with
/// whatever token it produced.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokenStore,
    required Dio retryClient,
    required Future<void> Function() onSessionExpired,
  })  : _tokenStore = tokenStore,
        _retryClient = retryClient,
        _onSessionExpired = onSessionExpired;

  final TokenStore _tokenStore;

  /// A Dio with no auth interceptor, used for the refresh call and for
  /// replaying the original request. Using the main client would recurse.
  final Dio _retryClient;

  final Future<void> Function() _onSessionExpired;

  Future<String?>? _refreshOperation;

  /// Endpoints that must never carry a stale bearer token or trigger a refresh.
  static const _unauthenticatedPaths = <String>{
    ApiEndpoints.login,
    ApiEndpoints.register,
    ApiEndpoints.sendOtp,
    ApiEndpoints.verifyOtp,
    ApiEndpoints.refreshToken,
    ApiEndpoints.forgotPassword,
    ApiEndpoints.resetPassword,
    ApiEndpoints.businessContact,
    ApiEndpoints.appConfig,
    ApiEndpoints.health,
  };

  bool _isUnauthenticated(RequestOptions options) =>
      _unauthenticatedPaths.any((path) => options.path.startsWith(path));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokenStore.accessToken;
    if (token != null && token.isNotEmpty && !_isUnauthenticated(options)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final isUnauthorized = response?.statusCode == 401;

    if (!isUnauthorized || _isUnauthenticated(err.requestOptions)) {
      return handler.next(err);
    }

    // Already retried once; a second 401 means refreshing did not help.
    if (err.requestOptions.extra['__retried_after_refresh'] == true) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final code = response?.data is Map ? (response!.data as Map)['code'] : null;

    // Codes that mean "this session is finished" rather than "token is stale".
    // Refreshing would not help, so sign out immediately.
    const unrecoverable = {
      'TOKEN_REVOKED',
      'REFRESH_TOKEN_REUSED',
      'REFRESH_TOKEN_INVALID',
      'REFRESH_TOKEN_EXPIRED',
      'ACCOUNT_NOT_FOUND',
      'ACCOUNT_SUSPENDED',
    };

    if (unrecoverable.contains(code)) {
      await _onSessionExpired();
      return handler.next(err);
    }

    if (!_tokenStore.hasSession) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final newToken = await _refreshAccessToken();

    if (newToken == null) {
      return handler.next(err);
    }

    try {
      final request = err.requestOptions;
      final retried = await _retryClient.fetch<dynamic>(
        request.copyWith(
          headers: {...request.headers, 'Authorization': 'Bearer $newToken'},
          extra: {...request.extra, '__retried_after_refresh': true},
        ),
      );
      return handler.resolve(retried);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  /// Refreshes the access token, coalescing concurrent callers onto one request.
  Future<String?> _refreshAccessToken() {
    // Someone is already refreshing; wait for their result.
    final inFlight = _refreshOperation;
    if (inFlight != null) return inFlight;

    final operation = _performRefresh();
    _refreshOperation = operation;

    // Clear the slot once settled, so the next expiry starts a fresh attempt.
    operation.whenComplete(() {
      if (_refreshOperation == operation) _refreshOperation = null;
    });

    return operation;
  }

  Future<String?> _performRefresh() async {
    final refreshToken = _tokenStore.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _onSessionExpired();
      return null;
    }

    try {
      final response = await _retryClient.post<dynamic>(
        ApiEndpoints.refreshToken,
        data: {'refreshToken': refreshToken},
      );

      final data = response.data is Map ? (response.data as Map)['data'] : null;
      if (data is! Map) {
        await _onSessionExpired();
        return null;
      }

      final newAccessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;

      if (newAccessToken == null || newAccessToken.isEmpty) {
        await _onSessionExpired();
        return null;
      }

      // The backend rotates refresh tokens, so store the new one too or the
      // next refresh will present a revoked token.
      if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
        await _tokenStore.saveTokens(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
        );
      } else {
        await _tokenStore.saveAccessToken(newAccessToken);
      }

      return newAccessToken;
    } on DioException catch (error) {
      // A network failure during refresh is not a sign-out; the session may
      // still be perfectly valid once connectivity returns.
      final status = error.response?.statusCode;
      final isTransport = error.type != DioExceptionType.badResponse;

      if (isTransport || (status != null && status >= 500)) {
        if (AppConfig.debugLogging) {
          // ignore: avoid_print
          print('[auth] refresh failed transiently: ${error.type}');
        }
        return null;
      }

      await _onSessionExpired();
      return null;
    } on Object {
      await _onSessionExpired();
      return null;
    }
  }
}
