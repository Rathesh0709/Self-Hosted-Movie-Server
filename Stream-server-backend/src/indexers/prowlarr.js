import axios from "axios";

const PROWLARR_URL = process.env.PROWLARR_URL || "http://localhost:9696";
const API_KEY = process.env.PROWLARR_API_KEY || "";

function extractInfoHash(magnet) {
  if (!magnet) return null;
  const match = magnet.match(/urn:btih:([a-zA-Z0-9]+)/i);
  return match ? match[1].toLowerCase() : null;
}

function parseSize(sizeBytes) {
  if (!sizeBytes) return 'Unknown Size';
  const mb = sizeBytes / (1024 * 1024);
  if (mb > 1024) return (mb / 1024).toFixed(2) + ' GB';
  return mb.toFixed(2) + ' MB';
}

// Indexer names (lowercase substring) that ONLY handle anime. Sending a
// non-anime query to these stalls the whole Prowlarr search, so we route them
// in/out based on whether the request is for anime.
const ANIME_ONLY_INDEXERS = ['nyaa'];

let _indexerCache = null; // { all: number[], animeOnly: number[], nonAnime: number[] }

async function getIndexerBuckets() {
  if (_indexerCache) return _indexerCache;
  try {
    const res = await axios.get(`${PROWLARR_URL}/api/v1/indexer`, {
      headers: { "X-Api-Key": API_KEY },
      timeout: 8000,
    });
    const indexers = res.data || [];
    const all = [];
    const animeOnly = [];
    const nonAnime = [];
    for (const ix of indexers) {
      if (ix.id === undefined || ix.id === null) continue;
      const name = (ix.name || '').toLowerCase();
      const isAnimeOnly = ANIME_ONLY_INDEXERS.some(n => name.includes(n));
      all.push(ix.id);
      if (isAnimeOnly) animeOnly.push(ix.id);
      else nonAnime.push(ix.id);
    }
    _indexerCache = { all, animeOnly, nonAnime };
    console.log(`[Prowlarr] Indexers — total: ${all.length}, anime-only: ${animeOnly.length}`);
    return _indexerCache;
  } catch (err) {
    console.error('[Prowlarr] Failed to load indexer list:', err.response?.data || err.message);
    return null; // fall back to searching everything
  }
}

export async function searchProwlarr(query, anime = false) {
  try {
    // Restrict which indexers run: anime-only indexers (nyaa) are included only
    // for anime requests; non-anime requests skip them so they don't stall.
    const buckets = await getIndexerBuckets();
    const params = { query };
    if (buckets) {
      const ids = anime ? buckets.all : buckets.nonAnime;
      if (ids.length > 0) params.indexerIds = ids;
    }

    console.log(`[Prowlarr] Searching: ${query} (anime: ${anime})`);
    const response = await axios.get(`${PROWLARR_URL}/api/v1/search`, {
      params,
      paramsSerializer: { indexes: null }, // indexerIds=1&indexerIds=2 (Prowlarr style)
      headers: { "X-Api-Key": API_KEY }
    });

    const results = response.data || [];
    console.log(`[Prowlarr] Found ${results.length} results`);

    const streams = [];
    const seenHashes = new Set();

    for (const result of results) {
      const magnetUrl = (result.guid && result.guid.startsWith('magnet:?')) ? result.guid : result.magnetUrl;
      const infoHash = (result.infoHash || extractInfoHash(magnetUrl))?.toLowerCase();
      
      if (infoHash && !seenHashes.has(infoHash)) {
        seenHashes.add(infoHash);
        
        streams.push({
          infoHash,
          title: result.title || 'Unknown Title',
          quality: /1080p/i.test(result.title) ? '1080p' : /720p/i.test(result.title) ? '720p' : /2160p|4k/i.test(result.title) ? '4K' : 'HDRip',
          size: parseSize(result.size),
          seeders: result.seeders ? result.seeders.toString() : '0',
          source: `Prowlarr | ${result.indexer || 'Unknown'}`,
          codec: /hevc|x265/i.test(result.title) ? 'x265' : 'x264',
          magnetUrl
        });
      }
    }

    return streams;
  } catch (err) {
    console.error('[Prowlarr] Search failed:', err.response?.data || err.message);
    return [];
  }
}
