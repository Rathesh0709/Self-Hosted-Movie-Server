import 'package:dio/dio.dart';
import '../core/network/dio_clients.dart';
import '../core/storage.dart';
import '../models/stream.dart';

/// Talks to our streaming backend. Port of backendService.ts.
class BackendService {
  final _dio = ApiClients.instance.backend;

  String get _base => AppStorage.instance.backendUrl.replaceAll(RegExp(r'/$'), '');

  Future<BackendStreamResponse> startStream(String magnetURI, {int? fileIdx}) async {
    final res = await _dio.post('/api/stream/start',
        data: {'magnetURI': magnetURI, 'fileIdx': ?fileIdx});
    return BackendStreamResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> downloadTorrent(String magnetURI, {int? fileIdx}) async {
    final res = await _dio.post('/api/stream/download',
        data: {'magnetURI': magnetURI, 'fileIdx': ?fileIdx});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<BackendStreamResponse> startFileStream(String filePath) async {
    final res = await _dio.post('/api/stream/file/start', data: {'filePath': filePath});
    return BackendStreamResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// Build a playable absolute URL from a backend-relative `stream` path.
  String playableUrl(String streamPath) {
    final path = streamPath.startsWith('/') ? streamPath : '/$streamPath';
    return '$_base$path';
  }

  /// Resolve a possibly-relative or localhost stream URL against the
  /// configured backend (port of resolveBackendUrl).
  String resolveBackendUrl(String streamOrPath) {
    if (streamOrPath.isEmpty) return _base;
    if (streamOrPath.startsWith('/')) return '$_base$streamOrPath';
    final uri = Uri.tryParse(streamOrPath);
    if (uri != null && uri.hasScheme) {
      const local = {'localhost', '127.0.0.1', '::1'};
      if (local.contains(uri.host)) {
        return '$_base${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      }
      return streamOrPath;
    }
    return '$_base/${streamOrPath.replaceFirst(RegExp(r'^/'), '')}';
  }

  /// Verify backend reachability against an arbitrary [url] (used for
  /// auto-discovery + settings test). Uses a throwaway client.
  Future<bool> testConnection(String url) async {
    try {
      final tmp = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'ngrok-skip-browser-warning': 'true', 'Accept': 'application/json'},
      ));
      final res = await tmp.get('/api/health');
      if (res.data is String) return false; // ngrok interstitial HTML
      return res.data is Map && res.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DownloadedFile>> getDownloadedFiles() async {
    final res = await _dio.get('/api/stream/files');
    final d = res.data;
    if (d is! Map || d['success'] != true) {
      throw Exception('Backend returned invalid response (offline)');
    }
    return ((d['files'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DownloadedFile.fromJson)
        .toList();
  }

  Future<List<ActiveDownload>> getActiveDownloads() async {
    final res = await _dio.get('/api/stream/downloads');
    return (((res.data as Map)['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ActiveDownload.fromJson)
        .toList();
  }

  String fileStreamUrl(String filePath) => '$_base/api/stream/file/$filePath';

  Future<List<ParsedStream>> searchIndexers(
    String query, {
    String? year,
    bool indian = false,
    bool anime = false,
    int? season,
    int? episode,
  }) async {
    // TamilMV scrapes the site live and extracts magnets per topic, which can
    // take well over a minute. The timeout that was killing this request lives
    // in Dio's WEB adapter: it sets the browser XHR's hard timeout to
    // `(connectTimeout + receiveTimeout)` total wall-clock ms. The base backend
    // client uses connectTimeout: 10s, so unless BOTH are overridden here the
    // XHR aborts mid-scrape (browser counts total elapsed, not idle, time).
    // `Duration.zero` on both → `xhr.timeout = 0` → no limit in the browser,
    // and on native it disables the timeout too. So the request now runs to
    // completion instead of being torn down halfway.
    final res = await _dio.get('/api/indexers/search',
        queryParameters: {
          'query': query,
          'year': ?year,
          'indian': indian ? 'true' : 'false',
          'anime': anime ? 'true' : 'false',
          'season': ?season,
          'episode': ?episode,
        },
        options: Options(
          connectTimeout: Duration.zero,
          receiveTimeout: Duration.zero,
        ));
    return (((res.data as Map)['streams'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ParsedStream.fromBackend)
        .toList();
  }

  Future<Map<String, dynamic>> resolveAnimeEpisode(String magnetURI, int episode) async {
    final res = await _dio
        .post('/api/indexers/resolve-episode', data: {'magnetURI': magnetURI, 'episode': episode});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> reportSeek(String streamId, int byteOffset) async {
    try {
      await _dio.post('/api/stream/$streamId/seek', data: {'byteOffset': byteOffset});
    } catch (_) {}
  }

  Future<StreamStatus?> getStreamHealth(String streamId) async {
    try {
      final res = await _dio.get('/api/stream/$streamId/status');
      if (res.data is Map && res.data['success'] == true) {
        return StreamStatus.fromJson((res.data as Map).cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  // ---- subtitles (torrent-embedded) ----
  Future<List<SubtitleEntry>> getTorrentSubtitles(String streamId) async {
    try {
      final res = await _dio.get('/api/stream/$streamId/subtitles');
      final subs = (((res.data as Map)['subtitles'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      return subs
          .map((s) => SubtitleEntry(
                label: (s['name'] ?? 'Subtitle') as String,
                url: '$_base/api/stream/$streamId/subtitle/${s['idx']}',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

final backendService = BackendService();
