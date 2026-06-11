// ============================================================
// App-wide constants — ported from the React app's
// src/utils/constants.ts
// ============================================================

/// TMDB image CDN base.
const String kTmdbImageBase = 'https://image.tmdb.org/t/p/';

/// TMDB API base.
const String kTmdbApiBase = 'https://api.themoviedb.org/3';

/// Public stream indexers.
const String kTorrentioBase = 'https://torrentio.strem.fun';
const String kTorrentsDbBase = 'https://torrentsdb.com';

/// Hardcoded Wake-on-LAN HTTP endpoint (same as wakeService.ts).
/// Public HTTPS tunnel so the app can wake the server from anywhere — no VPN.
const String kWakeUrl = 'https://wol.rathesh.dev/wake';

/// Image size presets keyed by [type] then logical size.
const Map<String, Map<String, String>> kImageSizes = {
  'poster': {'small': 'w185', 'medium': 'w342', 'large': 'w500', 'original': 'original'},
  'backdrop': {'small': 'w300', 'medium': 'w780', 'large': 'w1280', 'original': 'original'},
  'profile': {'small': 'w45', 'medium': 'w185', 'large': 'h632', 'original': 'original'},
};

/// TMDB genre id → display name.
const Map<int, String> kGenreMap = {
  28: 'Action',
  12: 'Adventure',
  16: 'Animation',
  35: 'Comedy',
  80: 'Crime',
  99: 'Documentary',
  18: 'Drama',
  10751: 'Family',
  14: 'Fantasy',
  36: 'History',
  27: 'Horror',
  10402: 'Music',
  9648: 'Mystery',
  10749: 'Romance',
  878: 'Sci-Fi',
  10770: 'TV Movie',
  53: 'Thriller',
  10752: 'War',
  37: 'Western',
  10759: 'Action & Adventure',
  10762: 'Kids',
  10763: 'News',
  10764: 'Reality',
  10765: 'Sci-Fi & Fantasy',
  10766: 'Soap',
  10767: 'Talk',
  10768: 'War & Politics',
};

/// Quality tier ordering (best → worst) used to sort/badge streams.
const List<String> kQualityOrder = ['4K', '2160p', '1080p', '720p', '480p', 'CAM', 'TS', 'SCR'];

/// Quality badge accent colors (hex without alpha).
const Map<String, int> kQualityColors = {
  '4K': 0xFFE8B4B8,
  '2160p': 0xFFE8B4B8,
  '1080p': 0xFF7DD3FC,
  '720p': 0xFF86EFAC,
  '480p': 0xFFFCD34D,
  'CAM': 0xFFF87171,
  'TS': 0xFFF87171,
  'SCR': 0xFFFBBF24,
};

/// Default backend URL — the static Cloudflare tunnel (public HTTPS, no VPN).
const String kDefaultBackendUrl = 'https://streamflix.rathesh.dev';

/// Backend candidate URLs tried during auto-discovery (App.tsx effect).
/// The Cloudflare tunnel is primary; the Tailscale IP + LAN are fallbacks for
/// when the tunnel is down but you're on the same network.
/// `<host>` style local discovery is added dynamically at runtime.
const List<String> kBackendDiscoveryUrls = [
  'https://streamflix.rathesh.dev/',
  'http://100.116.171.83:3000/', // Tailscale backup
  'http://192.168.1.7:3000/',
  'http://localhost:3000/',
  'http://10.0.2.2:3000/', // Android emulator → host loopback
];
