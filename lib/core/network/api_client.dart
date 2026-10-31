import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Thin wrapper over [Dio] that unwraps the backend's response envelope and
/// turns every failure into an [ApiException].
///
/// The backend always answers `{ success, message, data }`, so repositories
/// should never have to reach through `response.data['data']` themselves, and
/// should never see a [DioException].
class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  Dio get raw => _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query, cancelToken: cancelToken));

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    bool retryable = false,
  }) =>
      _send(() => _dio.post<dynamic>(
            path,
            data: body,
            queryParameters: query,
            cancelToken: cancelToken,
            options: Options(extra: {'retryable': retryable}),
          ));

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.put<dynamic>(path, data: body, cancelToken: cancelToken));

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.delete<dynamic>(path, data: body, cancelToken: cancelToken));

  /// Runs the call and returns the `data` object, or `{}` when the endpoint
  /// returned `data: null`.
  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      final body = response.data;

      if (body is! Map) {
        // Shape we do not recognise - most likely a proxy or captive portal
        // answering instead of the API.
        throw const ApiException(
          message: 'The server returned an unexpected response.',
          code: 'MALFORMED_RESPONSE',
        );
      }

      final data = body['data'];
      if (data == null) return <String, dynamic>{};
      if (data is Map) return Map<String, dynamic>.from(data);

      // A non-object `data` (a bare list or scalar). Wrap it so callers always
      // receive a map.
      return <String, dynamic>{'value': data};
    } on DioException catch (error) {
      throw ApiException.from(error);
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw ApiException.unexpected(error);
    }
  }

  /// Status code and message from the last call are not exposed; where a caller
  /// needs the HTTP status (booking creation distinguishes 201 from 200), use
  /// [postRaw] and read it from the response.
  Future<Response<dynamic>> postRaw(
    String path, {
    Object? body,
    CancelToken? cancelToken,
    bool retryable = false,
  }) async {
    try {
      return await _dio.post<dynamic>(
        path,
        data: body,
        cancelToken: cancelToken,
        options: Options(extra: {'retryable': retryable}),
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    } on Object catch (error) {
      throw ApiException.unexpected(error);
    }
  }
}
