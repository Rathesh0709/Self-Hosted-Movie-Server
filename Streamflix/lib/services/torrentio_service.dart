import '../core/constants.dart';
import '../core/network/dio_clients.dart';
import '../models/stream.dart';

/// Public-indexer stream lookups (Torrentio + TorrentsDB).
/// Ports of torrentioService.ts and torrentsdbService.ts.
class TorrentioService {
  final _dio = ApiClients.instance.indexer;

  Future<List<ParsedStream>> _fetch(String base, String path,
      {bool torrentsDb = false}) async {
    final res = await _dio.get('$base$path');
    final streams = (res.data is Map ? res.data['streams'] : null) as List?;
    if (streams == null) return const [];
    return streams.cast<Map<String, dynamic>>().map((s) {
      final parsed = ParsedStream.fromTorrentio(s);
      if (torrentsDb && !parsed.source.toLowerCase().contains('torrentsdb')) {
        return ParsedStream(
          infoHash: parsed.infoHash,
          quality: parsed.quality,
          size: parsed.size,
          seeders: parsed.seeders,
          source: 'TorrentsDB | ${parsed.source}',
          codec: parsed.codec,
          title: parsed.title,
          fileIdx: parsed.fileIdx,
          sources: (s['sources'] as List?)
              ?.whereType<String>()
              .where((e) => e.startsWith('tracker:'))
              .map((e) => e.replaceFirst('tracker:', ''))
              .toList(),
        );
      }
      return parsed;
    }).toList();
  }

  Future<List<ParsedStream>> getMovieStreams(String imdbId, {bool torrentsDb = false}) {
    if (imdbId.isEmpty) return Future.value(const []);
    final base = torrentsDb ? kTorrentsDbBase : kTorrentioBase;
    return _fetch(base, '/stream/movie/$imdbId.json', torrentsDb: torrentsDb);
  }

  Future<List<ParsedStream>> getShowStreams(String imdbId, int season, int episode,
      {bool torrentsDb = false}) {
    if (imdbId.isEmpty) return Future.value(const []);
    final base = torrentsDb ? kTorrentsDbBase : kTorrentioBase;
    return _fetch(base, '/stream/series/$imdbId:$season:$episode.json', torrentsDb: torrentsDb);
  }

  /// Build a magnet URI from a [ParsedStream] (adds public trackers).
  static String magnetUri(ParsedStream stream) {
    if (stream.magnetUrl != null && stream.magnetUrl!.isNotEmpty) return stream.magnetUrl!;
    var uri = 'magnet:?xt=urn:btih:${stream.infoHash}';
    if (stream.title.isNotEmpty) uri += '&dn=${Uri.encodeComponent(stream.title)}';
    final trackers = (stream.sources != null && stream.sources!.isNotEmpty)
        ? stream.sources!
        : const [
            'udp://tracker.opentrackr.org:1337/announce',
            'udp://tracker.coppersurfer.tk:6969/announce',
            'udp://open.demonii.com:1337/announce',
            'udp://tracker.leechers-paradise.org:6969/announce',
            'udp://open.stealth.si:80/announce',
            'udp://glotorrents.pw:6969/announce',
            'udp://tracker.cyberia.is:6969/announce',
          ];
    for (final t in trackers) {
      uri += '&tr=${Uri.encodeComponent(t)}';
    }
    return uri;
  }
}

final torrentioService = TorrentioService();
