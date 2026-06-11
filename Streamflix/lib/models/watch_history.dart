/// A single watch-history record (React WatchHistoryItem).
class WatchHistoryItem {
  final String id; // `${mediaType}-${mediaId}`
  final int mediaId;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final double progress; // 0..1
  final double currentTime; // seconds
  final double duration; // seconds
  final String? streamId;
  final String? streamUrl;
  final String? magnetURI;
  final int? fileIdx;
  final int lastWatched; // epoch ms
  final int? season;
  final int? episode;

  const WatchHistoryItem({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.progress = 0,
    this.currentTime = 0,
    this.duration = 0,
    this.streamId,
    this.streamUrl,
    this.magnetURI,
    this.fileIdx,
    this.lastWatched = 0,
    this.season,
    this.episode,
  });

  WatchHistoryItem copyWith({
    String? title,
    String? posterPath,
    String? backdropPath,
    double? progress,
    double? currentTime,
    double? duration,
    int? lastWatched,
  }) =>
      WatchHistoryItem(
        id: id,
        mediaId: mediaId,
        mediaType: mediaType,
        title: title ?? this.title,
        posterPath: posterPath ?? this.posterPath,
        backdropPath: backdropPath ?? this.backdropPath,
        progress: progress ?? this.progress,
        currentTime: currentTime ?? this.currentTime,
        duration: duration ?? this.duration,
        streamId: streamId,
        streamUrl: streamUrl,
        magnetURI: magnetURI,
        fileIdx: fileIdx,
        lastWatched: lastWatched ?? this.lastWatched,
        season: season,
        episode: episode,
      );

  factory WatchHistoryItem.fromJson(Map<String, dynamic> j) => WatchHistoryItem(
        id: (j['id'] ?? '') as String,
        mediaId: (j['mediaId'] as num).toInt(),
        mediaType: (j['mediaType'] ?? 'movie') as String,
        title: (j['title'] ?? '') as String,
        posterPath: j['poster_path'] as String? ?? j['posterPath'] as String?,
        backdropPath: j['backdrop_path'] as String? ?? j['backdropPath'] as String?,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        currentTime: (j['currentTime'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        streamId: j['streamId'] as String?,
        streamUrl: j['streamUrl'] as String?,
        magnetURI: j['magnetURI'] as String?,
        fileIdx: (j['fileIdx'] as num?)?.toInt(),
        lastWatched: (j['lastWatched'] as num?)?.toInt() ?? 0,
        season: (j['season'] as num?)?.toInt(),
        episode: (j['episode'] as num?)?.toInt(),
      );

  /// JSON shape expected by the backend (poster_path / backdrop_path snake_case).
  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaId': mediaId,
        'mediaType': mediaType,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'progress': progress,
        'currentTime': currentTime,
        'duration': duration,
        'streamId': streamId,
        'streamUrl': streamUrl,
        'magnetURI': magnetURI,
        'fileIdx': fileIdx,
        'lastWatched': lastWatched,
        'season': season,
        'episode': episode,
      };
}
