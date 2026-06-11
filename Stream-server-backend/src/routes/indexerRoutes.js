import express from 'express';
import { searchTamilMv } from '../indexers/tamilmv.js';
import { searchProwlarr } from '../indexers/prowlarr.js';
import { resolveAnimeEpisode } from '../indexers/animeResolver.js';

const router = express.Router();

router.get('/search', async (req, res) => {
  try {
    const { query, year, indian, anime, season, episode } = req.query;
    if (!query) return res.status(400).json({ success: false, error: 'Query required' });

    let searchQuery = query;
    if (season !== undefined && episode !== undefined) {
      // If episode > 100, it's likely an anime, append absolute episode
      if (parseInt(episode, 10) > 100) {
        searchQuery = `${query} ${episode}`;
      } else {
        const s = String(season).padStart(2, '0');
        const e = String(episode).padStart(2, '0');
        searchQuery = `${query} S${s}E${e}`;
      }
    }

    const isIndian = indian === 'true';
    const isAnime = anime === 'true';
    console.log(`[Indexer API] Unified Search: ${searchQuery} (Year: ${year}, Indian: ${isIndian}, Anime: ${isAnime})`);

    // Always search Prowlarr (anime-only indexers like nyaa are gated by the
    // anime flag inside searchProwlarr); only search TamilMV for Indian content
    const searches = [searchProwlarr(searchQuery, isAnime)];
    if (isIndian) {
      searches.push(searchTamilMv(query, year));
    }

    const results = await Promise.all(searches.map(p => p.catch(() => [])));
    const combinedStreams = results.flat();

    res.json({
      success: true,
      streams: combinedStreams
    });

  } catch (err) {
    console.error('[Indexer API] Search Error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/resolve-episode', async (req, res) => {
  try {
    const { magnetURI, episode } = req.body;
    if (!magnetURI || episode === undefined) {
      return res.status(400).json({ success: false, error: 'magnetURI and episode required' });
    }

    const result = await resolveAnimeEpisode(magnetURI, parseInt(episode, 10));
    res.json({ success: true, ...result });
  } catch (err) {
    console.error('[Indexer API] Resolve Episode Error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

export default router;
