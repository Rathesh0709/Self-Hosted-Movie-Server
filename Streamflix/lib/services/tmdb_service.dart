import '../core/constants.dart';
import '../core/network/dio_clients.dart';
import '../core/utils/formatters.dart';
import '../models/media.dart';
import '../models/credits.dart';

/// Build a TMDB image URL, with graceful Unsplash fallbacks (mirrors
/// getTmdbImageUrl in tmdbService.ts).
String tmdbImage(
  String? path, {
  String type = 'poster',
  String size = 'medium',
}) {
  if (path == null || path.isEmpty) {
    return type == 'poster'
        ? 'https://images.unsplash.com/photo-1594909122845-11baa439b7bf?q=80&w=342&auto=format&fit=crop'
        : 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=780&auto=format&fit=crop';
  }
  final sizeStr = kImageSizes[type]?[size] ?? 'w342';
  return '$kTmdbImageBase$sizeStr$path';
}

class TmdbService {
  final _dio = ApiClients.instance.tmdb;

  Future<List<MediaItem>> _list(
    String path, {
    Map<String, dynamic>? params,
    String? mediaType,
    bool filterMedia = false,
  }) async {
    final res = await _dio.get(path, queryParameters: params);
    final results = ((res.data['results'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return results
        .where((j) => !filterMedia ||
            j['media_type'] == 'movie' ||
            j['media_type'] == 'tv')
        .map((j) => MediaItem.fromTmdb(j, mediaType: mediaType))
        .toList();
  }

  Future<List<MediaItem>> getTrending(
          {String type = 'all', String timeWindow = 'day', int page = 1}) =>
      _list('/trending/$type/$timeWindow',
          params: {'page': page},
          mediaType: type == 'all' ? null : type,
          filterMedia: type == 'all');

  Future<List<MediaItem>> getPopular(String type, {int page = 1}) =>
      _list('/$type/popular', params: {'page': page}, mediaType: type);

  Future<List<MediaItem>> getTopRated(String type, {int page = 1}) =>
      _list('/$type/top_rated', params: {'page': page}, mediaType: type);

  Future<List<MediaItem>> getAnime({int page = 1}) => _list('/discover/tv',
      params: {'page': page, 'with_genres': 16, 'with_origin_country': 'JP'},
      mediaType: 'tv');

  Future<List<MediaItem>> getCartoons({int page = 1}) => _list('/discover/tv',
      params: {'page': page, 'with_genres': 16, 'without_origin_country': 'JP'},
      mediaType: 'tv');

  Future<List<MediaItem>> getPopularToday({int page = 1}) =>
      getTrending(type: 'all', timeWindow: 'day', page: page);

  Future<List<MediaItem>> search(String query, {int page = 1}) {
    if (query.trim().isEmpty) return Future.value(const []);
    return _list('/search/multi',
        params: {'query': query, 'page': page}, filterMedia: true);
  }

  Future<MovieDetails> getMovieDetails(int id) async {
    final res = await _dio.get('/movie/$id');
    return MovieDetails.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TVDetails> getTVDetails(int id) async {
    final res = await _dio.get('/tv/$id',
        queryParameters: {'append_to_response': 'external_ids'});
    return TVDetails.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Credits> getCredits(String type, int id) async {
    final res = await _dio.get('/$type/$id/credits');
    return Credits.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SeasonDetails> getSeasonDetails(int showId, int seasonNumber) async {
    final res = await _dio.get('/tv/$showId/season/$seasonNumber');
    return SeasonDetails.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String?> getImdbId(String type, int id) async {
    if (type == 'movie') {
      return (await getMovieDetails(id)).imdbId;
    }
    return (await getTVDetails(id)).imdbId;
  }

  /// Find artwork for a raw filename title (Continue-Watching backfill).
  Future<MediaItem?> findArtworkByTitle(String rawTitle) async {
    final query = normalizeTitle(rawTitle);
    if (query.isEmpty) return null;
    final results = await search(query);
    if (results.isEmpty) return null;
    return results.firstWhere(
      (r) => r.posterPath != null || r.backdropPath != null,
      orElse: () => results.first,
    );
  }
}

final tmdbService = TmdbService();
