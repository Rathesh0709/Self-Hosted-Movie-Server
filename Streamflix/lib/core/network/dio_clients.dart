import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage.dart';

/// Configured Dio clients mirroring src/services/api.ts.
///
/// - [tmdb]    : TMDB v3, injects `api_key` from settings.
/// - [indexer] : generic client for Torrentio / TorrentsDB.
/// - [backend] : our streaming server; baseUrl + JWT resolved per-request.
class ApiClients {
  ApiClients._();
  static final ApiClients instance = ApiClients._();

  final Dio tmdb = Dio(BaseOptions(
    baseUrl: kTmdbApiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ))
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final key = AppStorage.instance.tmdbApiKey;
      if (key.isNotEmpty) {
        options.queryParameters = {...options.queryParameters, 'api_key': key};
      }
      handler.next(options);
    }));

  final Dio indexer = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  final Dio backend = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ))
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final s = AppStorage.instance;
      options.baseUrl = s.backendUrl;
      final token = s.authToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      options.headers['ngrok-skip-browser-warning'] = 'true';
      options.headers['Accept'] = 'application/json';
      handler.next(options);
    }));

  Dio get torrentio =>
      indexer; // shared instance; baseUrl passed per call
}
