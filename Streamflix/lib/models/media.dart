// ============================================================
// TMDB media models — ports of the interfaces in src/types/index.ts.
// Plain classes with manual fromJson (no codegen).
// ============================================================

double _toDouble(dynamic v) => v is num ? v.toDouble() : 0.0;
int? _toIntN(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

class Genre {
  final int id;
  final String name;
  const Genre({required this.id, required this.name});
  factory Genre.fromJson(Map<String, dynamic> j) =>
      Genre(id: j['id'] as int, name: (j['name'] ?? '') as String);
}

/// Unified card model used across carousels/grids (React `MediaItem`).
class MediaItem {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final String releaseDate;
  final String overview;
  final String mediaType; // 'movie' | 'tv'
  final List<int> genreIds;
  final List<String> originCountry;
  final String? streamId;
  final String? streamUrl;
  final String? imdbId;

  const MediaItem({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0,
    this.releaseDate = '',
    this.overview = '',
    required this.mediaType,
    this.genreIds = const [],
    this.originCountry = const [],
    this.streamId,
    this.streamUrl,
    this.imdbId,
  });

  MediaItem copyWith({String? imdbId, String? streamId, String? streamUrl}) => MediaItem(
        id: id,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
        overview: overview,
        mediaType: mediaType,
        genreIds: genreIds,
        originCountry: originCountry,
        streamId: streamId ?? this.streamId,
        streamUrl: streamUrl ?? this.streamUrl,
        imdbId: imdbId ?? this.imdbId,
      );

  /// Map a raw TMDB search/movie/tv json into a [MediaItem].
  /// Port of tmdbService.mapToMediaItem.
  factory MediaItem.fromTmdb(Map<String, dynamic> j, {String? mediaType}) {
    final type = mediaType ??
        (j['media_type'] as String?) ??
        (j['title'] != null ? 'movie' : 'tv');
    final title = (j['title'] ?? j['name'] ?? 'Untitled') as String;
    final release = (j['release_date'] ?? j['first_air_date'] ?? '') as String;

    final originCountry = <String>[
      ...((j['origin_country'] as List?)?.cast<String>() ?? const []),
      ...((j['production_countries'] as List?)
              ?.map((c) => (c as Map)['iso_3166_1'] as String)
              .toList() ??
          const []),
    ];

    final genreIds = <int>[
      ...((j['genre_ids'] as List?)?.map((e) => e as int).toList() ?? const []),
      ...((j['genres'] as List?)?.map((g) => (g as Map)['id'] as int).toList() ?? const []),
    ];

    return MediaItem(
      id: j['id'] as int,
      title: title,
      posterPath: j['poster_path'] as String?,
      backdropPath: j['backdrop_path'] as String?,
      voteAverage: _toDouble(j['vote_average']),
      releaseDate: release,
      overview: (j['overview'] ?? '') as String,
      mediaType: type,
      genreIds: genreIds,
      originCountry: originCountry,
    );
  }
}

/// Full movie detail (TMDB /movie/{id}).
class MovieDetails {
  final int id;
  final String? imdbId;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final int? runtime;
  final List<Genre> genres;
  final List<String> originCountry;

  const MovieDetails({
    required this.id,
    this.imdbId,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.releaseDate = '',
    this.voteAverage = 0,
    this.runtime,
    this.genres = const [],
    this.originCountry = const [],
  });

  factory MovieDetails.fromJson(Map<String, dynamic> j) => MovieDetails(
        id: j['id'] as int,
        imdbId: j['imdb_id'] as String?,
        title: (j['title'] ?? '') as String,
        overview: (j['overview'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        releaseDate: (j['release_date'] ?? '') as String,
        voteAverage: _toDouble(j['vote_average']),
        runtime: _toIntN(j['runtime']),
        genres: (j['genres'] as List?)
                ?.map((g) => Genre.fromJson(g as Map<String, dynamic>))
                .toList() ??
            const [],
        originCountry: <String>[
          ...((j['origin_country'] as List?)?.cast<String>() ?? const []),
          ...((j['production_countries'] as List?)
                  ?.map((c) => (c as Map)['iso_3166_1'] as String)
                  .toList() ??
              const []),
        ],
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
        overview: overview,
        mediaType: 'movie',
        genreIds: genres.map((g) => g.id).toList(),
        originCountry: originCountry,
        imdbId: imdbId,
      );
}

/// Full TV detail (TMDB /tv/{id}?append_to_response=external_ids).
class TVDetails {
  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String firstAirDate;
  final double voteAverage;
  final int numberOfSeasons;
  final List<int> episodeRunTime;
  final List<Genre> genres;
  final List<String> originCountry;
  final String? imdbId;

  const TVDetails({
    required this.id,
    required this.name,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.firstAirDate = '',
    this.voteAverage = 0,
    this.numberOfSeasons = 1,
    this.episodeRunTime = const [],
    this.genres = const [],
    this.originCountry = const [],
    this.imdbId,
  });

  factory TVDetails.fromJson(Map<String, dynamic> j) => TVDetails(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        overview: (j['overview'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        firstAirDate: (j['first_air_date'] ?? '') as String,
        voteAverage: _toDouble(j['vote_average']),
        numberOfSeasons: _toIntN(j['number_of_seasons']) ?? 1,
        episodeRunTime:
            (j['episode_run_time'] as List?)?.map((e) => e as int).toList() ?? const [],
        genres: (j['genres'] as List?)
                ?.map((g) => Genre.fromJson(g as Map<String, dynamic>))
                .toList() ??
            const [],
        originCountry: (j['origin_country'] as List?)?.cast<String>() ?? const [],
        imdbId: (j['external_ids'] as Map?)?['imdb_id'] as String?,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: name,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        releaseDate: firstAirDate,
        overview: overview,
        mediaType: 'tv',
        genreIds: genres.map((g) => g.id).toList(),
        originCountry: originCountry,
        imdbId: imdbId,
      );
}

class Episode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String airDate;
  final int? runtime;
  final double voteAverage;

  const Episode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    this.overview = '',
    this.stillPath,
    this.airDate = '',
    this.runtime,
    this.voteAverage = 0,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as int,
        episodeNumber: _toIntN(j['episode_number']) ?? 0,
        seasonNumber: _toIntN(j['season_number']) ?? 0,
        name: (j['name'] ?? '') as String,
        overview: (j['overview'] ?? '') as String,
        stillPath: j['still_path'] as String?,
        airDate: (j['air_date'] ?? '') as String,
        runtime: _toIntN(j['runtime']),
        voteAverage: _toDouble(j['vote_average']),
      );
}

class SeasonDetails {
  final int seasonNumber;
  final String name;
  final List<Episode> episodes;
  const SeasonDetails({required this.seasonNumber, required this.name, this.episodes = const []});

  factory SeasonDetails.fromJson(Map<String, dynamic> j) => SeasonDetails(
        seasonNumber: _toIntN(j['season_number']) ?? 1,
        name: (j['name'] ?? '') as String,
        episodes: (j['episodes'] as List?)
                ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
