import 'package:dio/dio.dart';
import '../core/network/dio_clients.dart';
import '../core/storage.dart';
import '../models/stream.dart';

/// OpenSubtitles lookups proxied through our backend (subtitleRoutes.js).
class SubtitleService {
  final _dio = ApiClients.instance.backend;
  String get _base => AppStorage.instance.backendUrl.replaceAll(RegExp(r'/$'), '');

  Future<List<SubtitleEntry>> search({String? imdbId, String? query, int? season, int? episode}) async {
    try {
      final res = await _dio.get('/api/subtitles/search', queryParameters: {
        if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
        if (query != null && query.isNotEmpty) 'query': query,
        'season': ?season,
        'episode': ?episode,
      });
      final subs = (((res.data as Map)['subtitles'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      return subs
          .where((s) => s['downloadLink'] != null)
          .map((s) => SubtitleEntry(
                label: (s['name'] ?? 'Subtitle') as String,
                downloads: s['downloads']?.toString(),
                // Backend decompresses + converts to VTT.
                url: '$_base/api/subtitles/download?url=${Uri.encodeComponent(s['downloadLink'] as String)}',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch the actual subtitle text (VTT) for a resolvable URL. We load the
  /// content ourselves and hand it to the player as `SubtitleTrack.data` rather
  /// than a URL — on web a cross-origin `<track>` URL won't load (the video
  /// element has no `crossorigin`), so passing the data directly is what makes
  /// server/torrent subtitles actually display.
  Future<String?> fetchContent(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final data = res.data;
      return (data == null || data.isEmpty) ? null : data;
    } catch (_) {
      return null;
    }
  }
}

final subtitleService = SubtitleService();
