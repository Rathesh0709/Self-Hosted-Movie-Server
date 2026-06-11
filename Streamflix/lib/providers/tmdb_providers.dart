import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media.dart';
import '../models/credits.dart';
import '../services/tmdb_service.dart';

// ---- Home / browse feeds (family by page) ----
final trendingProvider = FutureProvider.family<List<MediaItem>, ({String window, int page})>(
  (ref, a) => tmdbService.getTrending(type: 'all', timeWindow: a.window, page: a.page),
);

final popularProvider = FutureProvider.family<List<MediaItem>, ({String type, int page})>(
  (ref, a) => tmdbService.getPopular(a.type, page: a.page),
);

final topRatedProvider = FutureProvider.family<List<MediaItem>, ({String type, int page})>(
  (ref, a) => tmdbService.getTopRated(a.type, page: a.page),
);

final animeProvider =
    FutureProvider.family<List<MediaItem>, int>((ref, page) => tmdbService.getAnime(page: page));

final cartoonsProvider = FutureProvider.family<List<MediaItem>, int>(
    (ref, page) => tmdbService.getCartoons(page: page));

final popularTodayProvider = FutureProvider.family<List<MediaItem>, int>(
    (ref, page) => tmdbService.getPopularToday(page: page));

// ---- Search ----
final searchProvider =
    FutureProvider.family<List<MediaItem>, ({String query, int page})>((ref, a) {
  if (a.query.trim().isEmpty) return Future.value(const []);
  return tmdbService.search(a.query, page: a.page);
});

// ---- Details ----
final movieDetailsProvider =
    FutureProvider.family<MovieDetails, int>((ref, id) => tmdbService.getMovieDetails(id));

final tvDetailsProvider =
    FutureProvider.family<TVDetails, int>((ref, id) => tmdbService.getTVDetails(id));

final creditsProvider = FutureProvider.family<Credits, ({String type, int id})>(
    (ref, a) => tmdbService.getCredits(a.type, a.id));

final seasonProvider = FutureProvider.family<SeasonDetails, ({int showId, int season})>(
    (ref, a) => tmdbService.getSeasonDetails(a.showId, a.season));

final imdbIdProvider = FutureProvider.family<String?, ({String type, int id})>(
    (ref, a) => tmdbService.getImdbId(a.type, a.id));
