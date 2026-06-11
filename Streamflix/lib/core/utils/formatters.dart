// ============================================================
// Formatting helpers — ports of src/utils/formatters.ts plus
// the title normalizer from tmdbService.ts.
// ============================================================

/// Stable id for a watch-history entry: `${mediaType}-${mediaId}`.
String generateWatchId(String mediaType, int mediaId) => '$mediaType-$mediaId';

/// "2h 14m" / "47m" from a runtime in minutes.
String formatRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h <= 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Year portion of a TMDB date string ("2021-08-03" → "2021").
String formatYear(String? date) {
  if (date == null || date.isEmpty) return '';
  final parts = date.split('-');
  return parts.isNotEmpty ? parts.first : '';
}

/// Human file/byte size.
String formatBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// Normalize a raw torrent/file title into something searchable on TMDB.
/// Direct port of tmdbService.normalizeTitle.
String normalizeTitle(String rawTitle) {
  var clean = rawTitle.replaceAll(RegExp(r'\.[a-z0-9]{2,4}$', caseSensitive: false), '');

  final yearMatch = RegExp(
    r'^(.*?)(?=[\.\s\(\[\-_](?:19\d{2}|20\d{2})(?:[\.\s\)\]\-_]|$))',
  ).firstMatch(clean);
  if (yearMatch != null && (yearMatch.group(1)?.length ?? 0) > 1) {
    clean = yearMatch.group(1)!;
  }

  clean = clean
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(
        RegExp(
          r'\b(480p|720p|1080p|2160p|4k|x264|x265|hevc|webrip|bluray|brrip|hdrip|dvdrip|cam|telesync|aac|dts|hq|v\d+|psa|internal|multi|hc|esub|uncensored|dual|audio|hindi|english)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), ' ')
      .replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (clean.isNotEmpty) return clean;
  return rawTitle
      .replaceAll(RegExp(r'\.[a-z0-9]{2,4}$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[._]'), ' ')
      .trim();
}
