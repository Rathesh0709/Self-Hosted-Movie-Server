// ============================================================
// Torrent / backend stream models (ports from src/types/index.ts).
// ============================================================

/// A parsed torrent stream option shown in the selection sheet.
class ParsedStream {
  final String infoHash;
  final String quality;
  final String size;
  final String seeders;
  final String source;
  final String codec;
  final String title;
  final int? fileIdx;
  final List<String>? sources;
  final String? magnetUrl;

  const ParsedStream({
    required this.infoHash,
    this.quality = 'HDRip',
    this.size = 'Unknown Size',
    this.seeders = '0',
    this.source = 'Torrentio',
    this.codec = 'x264',
    this.title = '',
    this.fileIdx,
    this.sources,
    this.magnetUrl,
  });

  int get seedersInt => int.tryParse(seeders) ?? 0;

  /// Parse a Torrentio/TorrentsDB raw stream entry.
  /// Port of parseTorrentioTitle in torrentioService.ts.
  ///
  /// Torrentio's `title` is multi-line and its shape varies:
  ///  - movie  (2 lines): `name` then `👤 132 💾 443 MB ⚙️ Provider`
  ///  - episode(3 lines): `PACK name` then `episode file` then `👤 65 💾 … ⚙️ …`
  /// The old parser assumed line[0]=name and line[1]=stats, so for episodes it
  /// showed the whole-series PACK name and read 0 seeders / Unknown size (the
  /// stats are on line[2]). We instead locate the stats line by its 👤/💾/⚙️
  /// markers and prefer `behaviorHints.filename` (the exact episode file) for
  /// the display name.
  factory ParsedStream.fromTorrentio(Map<String, dynamic> s) {
    final raw = (s['title'] ?? '') as String;
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();

    bool isStatsLine(String l) =>
        l.contains('👤') ||
        l.contains('💾') ||
        l.contains('⚙️') ||
        RegExp(r'Seeders:\s*\d+').hasMatch(l);

    final statsLine = lines.firstWhere(isStatsLine, orElse: () => '');
    final nameLines = lines.where((l) => !isStatsLine(l)).toList();

    // Prefer the exact episode/movie file name from behaviorHints; otherwise use
    // the LAST non-stats line (the per-episode file in a pack), else the first.
    final hintName = ((s['behaviorHints'] as Map?)?['filename'] as String?)?.trim();
    final filename = (hintName != null && hintName.isNotEmpty)
        ? hintName
        : (nameLines.isNotEmpty
            ? nameLines.last
            : (lines.isNotEmpty ? lines.first : 'Unknown Torrent File'));

    String seeders = '0';
    final seedMatch = RegExp(r'👤\s*(\d+)').firstMatch(statsLine) ??
        RegExp(r'Seeders:\s*(\d+)').firstMatch(statsLine);
    if (seedMatch != null) seeders = seedMatch.group(1)!;

    String size = 'Unknown Size';
    final sizeMatch =
        RegExp(r'💾\s*([\d\.]+\s*(?:GB|MB|KB|B))', caseSensitive: false).firstMatch(statsLine) ??
            RegExp(r'Size:\s*([\d\.]+\s*(?:GB|MB|KB|B))', caseSensitive: false)
                .firstMatch(statsLine);
    if (sizeMatch != null) size = sizeMatch.group(1)!;

    String source = 'Torrentio';
    final provMatch = RegExp(r'⚙️\s*([^\s]+)').firstMatch(statsLine) ??
        RegExp(r'Provider:\s*([^\s]+)').firstMatch(statsLine);
    if (provMatch != null) source = provMatch.group(1)!;

    // Quality/codec/audio: scan the full title (pack names often carry the
    // quality tag, e.g. "[1080p]") plus the chosen filename.
    final tags = '${filename.toUpperCase()} ${raw.toUpperCase()}';

    String quality = 'HDRip';
    for (final q in ['2160p', '4K', '1080p', '720p', '480p', 'CAMRip', 'CAM', 'TS', 'SCR', 'HDR']) {
      if (tags.contains(q.toUpperCase())) {
        quality = q;
        break;
      }
    }

    String codec = 'x264';
    for (final c in ['HEVC', 'x265', 'h265', 'x264', 'h264', 'AVC']) {
      if (tags.contains(c.toUpperCase())) {
        codec = c;
        break;
      }
    }

    String audio = '';
    for (final a in ['DTS-HD', 'DTS', 'AAC', 'AC3', 'DD5.1', '5.1', 'TrueHD', 'Atmos']) {
      if (tags.contains(a.toUpperCase())) {
        audio = ' | $a';
        break;
      }
    }

    return ParsedStream(
      infoHash: (s['infoHash'] ?? '') as String,
      quality: quality,
      size: size,
      seeders: seeders,
      source: '$source$audio',
      codec: codec,
      title: filename,
      fileIdx: s['fileIdx'] as int?,
      sources: (s['sources'] as List?)?.cast<String>(),
    );
  }

  /// Parse from the backend indexer response (already in ParsedStream shape).
  factory ParsedStream.fromBackend(Map<String, dynamic> j) => ParsedStream(
        infoHash: (j['infoHash'] ?? '') as String,
        quality: (j['quality'] ?? 'HDRip') as String,
        size: (j['size'] ?? 'Unknown Size') as String,
        seeders: '${j['seeders'] ?? '0'}',
        source: (j['source'] ?? 'Indexer') as String,
        codec: (j['codec'] ?? 'x264') as String,
        title: (j['title'] ?? '') as String,
        fileIdx: j['fileIdx'] as int?,
        sources: (j['sources'] as List?)?.cast<String>(),
        magnetUrl: j['magnetUrl'] as String?,
      );
}

class BackendStreamResponse {
  final bool success;
  final String streamId;
  final String stream;
  const BackendStreamResponse({
    required this.success,
    required this.streamId,
    required this.stream,
  });
  factory BackendStreamResponse.fromJson(Map<String, dynamic> j) => BackendStreamResponse(
        success: j['success'] == true,
        streamId: (j['streamId'] ?? '') as String,
        stream: (j['stream'] ?? '') as String,
      );
}

class DownloadedFile {
  final String name;
  final String path;
  final int size;
  final num sizeMB;
  final bool needsTranscode;
  const DownloadedFile({
    required this.name,
    required this.path,
    this.size = 0,
    this.sizeMB = 0,
    this.needsTranscode = false,
  });
  factory DownloadedFile.fromJson(Map<String, dynamic> j) => DownloadedFile(
        name: (j['name'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        sizeMB: (j['sizeMB'] as num?) ?? 0,
        needsTranscode: j['needsTranscode'] == true,
      );
}

class ActiveDownload {
  final String name;
  final double progress;
  final int numPeers;
  final bool done;
  const ActiveDownload({
    required this.name,
    this.progress = 0,
    this.numPeers = 0,
    this.done = false,
  });
  factory ActiveDownload.fromJson(Map<String, dynamic> j) => ActiveDownload(
        name: (j['name'] ?? '') as String,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        numPeers: (j['numPeers'] as num?)?.toInt() ?? 0,
        done: j['done'] == true,
      );
}

class StreamStatus {
  final double bufferAheadSeconds;
  final double downloadSpeed;
  final double torrentProgress;
  final String health; // excellent | good | fair | poor
  const StreamStatus({
    this.bufferAheadSeconds = 0,
    this.downloadSpeed = 0,
    this.torrentProgress = 0,
    this.health = 'good',
  });
  factory StreamStatus.fromJson(Map<String, dynamic> j) => StreamStatus(
        bufferAheadSeconds: (j['bufferAheadSeconds'] as num?)?.toDouble() ?? 0,
        downloadSpeed: (j['downloadSpeed'] as num?)?.toDouble() ?? 0,
        torrentProgress: (j['torrentProgress'] as num?)?.toDouble() ?? 0,
        health: (j['health'] ?? 'good') as String,
      );
}

/// A subtitle entry (torrent-embedded or OpenSubtitles).
class SubtitleEntry {
  final String label;
  final String url; // resolvable backend URL serving VTT
  final String? downloads; // OpenSubtitles download count, when known
  const SubtitleEntry({required this.label, required this.url, this.downloads});
}
