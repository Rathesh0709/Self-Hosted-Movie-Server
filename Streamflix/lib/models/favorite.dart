import 'media.dart';

class FavoriteItem {
  final int mediaId;
  final String mediaType; // 'movie' | 'tv'
  final String? category; // movie | tv | anime | cartoon
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;

  const FavoriteItem({
    required this.mediaId,
    required this.mediaType,
    this.category,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(
        mediaId: (j['media_id'] as num).toInt(),
        mediaType: (j['media_type'] ?? 'movie') as String,
        category: j['category'] as String?,
        title: (j['title'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        voteAverage: (j['vote_average'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'media_id': mediaId,
        'media_type': mediaType,
        'category': category,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'vote_average': voteAverage,
      };

  MediaItem toMediaItem() => MediaItem(
        id: mediaId,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        mediaType: mediaType,
      );
}
