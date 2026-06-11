import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media.dart';
import '../models/stream.dart';
import '../services/torrentio_service.dart';
import '../services/backend_service.dart';

/// Query key for the aggregated stream search.
class StreamQuery {
  final MediaItem media;
  final String imdbId;
  final int? season;
  final int? episode;
  const StreamQuery(this.media, this.imdbId, {this.season, this.episode});

  @override
  bool operator ==(Object other) =>
      other is StreamQuery &&
      other.media.id == media.id &&
      other.imdbId == imdbId &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(media.id, imdbId, season, episode);
}

List<ParsedStream> _dedupeAndSort(List<ParsedStream> streams) {
  final seen = <String, ParsedStream>{};
  for (final s in streams) {
    final key = s.infoHash.toLowerCase();
    seen.putIfAbsent(key, () => s);
  }
  final list = seen.values.toList()
    ..sort((a, b) => b.seedersInt.compareTo(a.seedersInt));
  return list;
}

bool _isIndian(MediaItem m) => m.originCountry.contains('IN');

/// Anime = Japanese animation (genre 16 + origin JP). nyaa (a Prowlarr indexer)
/// only handles anime and stalls on non-anime queries, so the backend must only
/// route anime requests to it — we pass this flag so it can.
bool _isAnime(MediaItem m) => m.genreIds.contains(16) && m.originCountry.contains('JP');

String _normTitle(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Whether a text-searched indexer result actually belongs to [wantedTitle].
///
/// Torrentio / TorrentsDB query by IMDB id so they're always the right title,
/// but TamilMV / Prowlarr search by free text — so a search for "Karuppu" also
/// returns "Karuppu Pulsar". We take the NAME portion of the release title
/// (everything before the "(YYYY)" year tag or the first technical token) and
/// require it to equal the wanted title exactly, which keeps
/// "Karuppu (2026) …" but drops "Karuppu Pulsar (2026) …".
bool _indexerTitleMatches(String wantedTitle, String resultTitle) {
  final wanted = _normTitle(wantedTitle);
  if (wanted.isEmpty) return true;

  var head = resultTitle;
  // Strip leading bracketed/quality tags like "[4K]" or "(Tamil)" so they don't
  // hide the real name (e.g. "[4K] Karuppu Pulsar (2026)").
  head = head.replaceFirst(RegExp(r'^\s*(?:\[[^\]]*\]|\([^\)]*\))\s*'), '');
  final yearMatch = RegExp(r'\(?(?:19|20)\d{2}\)?').firstMatch(head);
  if (yearMatch != null) head = head.substring(0, yearMatch.start);
  // Cut at the first bracket / dash / pipe that introduces technical tokens.
  head = head.split(RegExp(r'[\[\(\-–|]')).first;

  final normHead = _normTitle(head);
  // If we couldn't isolate a name (no year/markers), fall back to a contains
  // check so we don't over-filter unusual title formats.
  if (normHead.isEmpty) return _normTitle(resultTitle).contains(wanted);
  return normHead == wanted;
}

/// Keep only indexer streams whose title matches [wantedTitle]. If filtering
/// would remove everything (e.g. the release names it very differently), keep
/// the originals rather than show nothing.
List<ParsedStream> _filterIndexerByTitle(List<ParsedStream> streams, String wantedTitle) {
  if (streams.isEmpty) return streams;
  final kept = streams.where((s) => _indexerTitleMatches(wantedTitle, s.title)).toList();
  return kept.isEmpty ? streams : kept;
}

/// Aggregates Torrentio + TorrentsDB + backend indexers (Prowlarr always,
/// TamilMV only for Indian content). Port of useStreams (useTorrentio.ts).
final streamsProvider =
    FutureProvider.family<List<ParsedStream>, StreamQuery>((ref, q) async {
  // Pin the result: this family auto-disposes by default, so any moment the
  // dialog has no active listener (e.g. between setState rebuilds for the
  // spinner) Riverpod would tear the provider down and RE-RUN it from scratch
  // — restarting a brand-new backend scrape and abandoning the in-flight one.
  // That's what produced the repeated "Unified Search" calls and the
  // half-finished request. keepAlive() stops the dispose/re-run churn so the
  // single TamilMV scrape runs to completion. (Refresh still re-fetches via
  // ref.invalidate.)
  ref.keepAlive();

  if (q.imdbId.isEmpty) return const [];
  final year = q.media.releaseDate.isNotEmpty ? q.media.releaseDate.split('-').first : null;
  final indian = _isIndian(q.media);
  final anime = _isAnime(q.media);

  Future<List<ParsedStream>> guard(Future<List<ParsedStream>> f) =>
      f.catchError((_) => <ParsedStream>[]);

  // The backend indexer search (Prowlarr + TamilMV) is slow — TamilMV scrapes
  // and extracts magnets from every matching topic, which can take a while.
  // Issue a SINGLE long-lived request and let it finish; firing repeat requests
  // just restarts (and "intercepts") the in-flight extraction on the server.
  final backendIndexers = guard(backendService.searchIndexers(
    q.media.title,
    year: year,
    indian: indian,
    anime: anime,
    season: q.season,
    episode: q.episode,
  ));

  // TorrentsDB aggregates fuzzy sub-providers (e.g. "TorrentsDB | 1tamilmv").
  // Title filtering is applied to MOVIES only: there the fuzzy indexers return
  // clean "Title (year)" names, so wrong-movie collisions (Karuppu → "Karuppu
  // Pulsar", "VeeraBhadrudu") are easy to drop. TV/anime results are episode
  // files (dotted, no year, S01E03 …) that the name filter can't parse safely,
  // and they're already episode-keyed, so we leave them unfiltered.
  if (q.media.mediaType == 'movie') {
    final results = await Future.wait([
      guard(torrentioService.getMovieStreams(q.imdbId)),
      guard(torrentioService.getMovieStreams(q.imdbId, torrentsDb: true))
          .then((s) => _filterIndexerByTitle(s, q.media.title)),
      backendIndexers.then((s) => _filterIndexerByTitle(s, q.media.title)),
    ]);
    return _dedupeAndSort(results.expand((e) => e).toList());
  } else {
    if (q.season == null || q.episode == null) return const [];
    final results = await Future.wait([
      guard(torrentioService.getShowStreams(q.imdbId, q.season!, q.episode!)),
      guard(torrentioService.getShowStreams(q.imdbId, q.season!, q.episode!, torrentsDb: true)),
      backendIndexers,
    ]);
    return _dedupeAndSort(results.expand((e) => e).toList());
  }
});
