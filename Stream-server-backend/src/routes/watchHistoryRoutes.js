import express from 'express';
import db from '../database/database.js';
import { requireAuth } from '../middleware/authMiddleware.js';

const router = express.Router();
router.use(requireAuth);

// GET /api/watch-history — fetch all watch history for the user
router.get('/', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT watch_id, media_id, media_type, title, poster_path, backdrop_path,
                progress, current_time, duration, stream_id, stream_url,
                magnet_uri, file_idx, last_watched, season, episode
         FROM watch_history
         WHERE user_id = ?
         ORDER BY last_watched DESC
         LIMIT 100`
      )
      .all(req.user.id);

    const items = rows.map((row) => ({
      id: row.watch_id,
      mediaId: row.media_id,
      mediaType: row.media_type,
      title: row.title,
      poster_path: row.poster_path,
      backdrop_path: row.backdrop_path,
      progress: row.progress,
      currentTime: row.current_time,
      duration: row.duration,
      streamId: row.stream_id,
      streamUrl: row.stream_url,
      magnetURI: row.magnet_uri,
      fileIdx: row.file_idx,
      lastWatched: row.last_watched,
      season: row.season,
      episode: row.episode,
    }));

    res.json({ success: true, items });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/watch-history — upsert a watch history item
router.put('/', (req, res) => {
  const item = req.body;
  if (!item || !item.id || !item.mediaId || !item.title) {
    return res.status(400).json({ success: false, error: 'id, mediaId, title are required' });
  }
  try {
    db.prepare(
      `INSERT INTO watch_history
       (user_id, watch_id, media_id, media_type, title, poster_path, backdrop_path,
        progress, current_time, duration, stream_id, stream_url, magnet_uri,
        file_idx, last_watched, season, episode, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id, watch_id) DO UPDATE SET
        title = excluded.title,
        poster_path = excluded.poster_path,
        backdrop_path = excluded.backdrop_path,
        progress = excluded.progress,
        current_time = excluded.current_time,
        duration = excluded.duration,
        stream_id = excluded.stream_id,
        stream_url = excluded.stream_url,
        magnet_uri = excluded.magnet_uri,
        file_idx = excluded.file_idx,
        last_watched = excluded.last_watched,
        season = excluded.season,
        episode = excluded.episode,
        updated_at = CURRENT_TIMESTAMP`
    ).run(
      req.user.id,
      item.id,
      item.mediaId,
      item.mediaType || 'movie',
      item.title,
      item.poster_path ?? null,
      item.backdrop_path ?? null,
      item.progress ?? 0,
      item.currentTime ?? 0,
      item.duration ?? 0,
      item.streamId ?? null,
      item.streamUrl ?? null,
      item.magnetURI ?? null,
      item.fileIdx ?? null,
      item.lastWatched ?? Date.now(),
      item.season ?? null,
      item.episode ?? null
    );
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/watch-history/:watchId — remove a single item
router.delete('/:watchId', (req, res) => {
  if (req.params.watchId === 'all') {
    try {
      db.prepare('DELETE FROM watch_history WHERE user_id = ?').run(req.user.id);
      return res.json({ success: true });
    } catch (error) {
      return res.status(500).json({ success: false, error: error.message });
    }
  }

  try {
    db.prepare('DELETE FROM watch_history WHERE user_id = ? AND watch_id = ?')
      .run(req.user.id, req.params.watchId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/watch-history/sync — bulk sync (client sends full history, server merges)
router.post('/sync', (req, res) => {
  const { items } = req.body ?? {};
  if (!Array.isArray(items)) {
    return res.status(400).json({ success: false, error: 'items array required' });
  }

  try {
    const upsert = db.prepare(
      `INSERT INTO watch_history
       (user_id, watch_id, media_id, media_type, title, poster_path, backdrop_path,
        progress, current_time, duration, stream_id, stream_url, magnet_uri,
        file_idx, last_watched, season, episode, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id, watch_id) DO UPDATE SET
        title = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.title ELSE watch_history.title END,
        poster_path = CASE WHEN excluded.poster_path IS NOT NULL THEN excluded.poster_path ELSE watch_history.poster_path END,
        backdrop_path = CASE WHEN excluded.backdrop_path IS NOT NULL THEN excluded.backdrop_path ELSE watch_history.backdrop_path END,
        progress = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.progress ELSE watch_history.progress END,
        current_time = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.current_time ELSE watch_history.current_time END,
        duration = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.duration ELSE watch_history.duration END,
        stream_id = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.stream_id ELSE watch_history.stream_id END,
        stream_url = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.stream_url ELSE watch_history.stream_url END,
        magnet_uri = CASE WHEN excluded.magnet_uri IS NOT NULL THEN excluded.magnet_uri ELSE watch_history.magnet_uri END,
        file_idx = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.file_idx ELSE watch_history.file_idx END,
        last_watched = MAX(excluded.last_watched, watch_history.last_watched),
        season = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.season ELSE watch_history.season END,
        episode = CASE WHEN excluded.last_watched > watch_history.last_watched THEN excluded.episode ELSE watch_history.episode END,
        updated_at = CURRENT_TIMESTAMP`
    );

    const runSync = db.transaction((userId, clientItems) => {
      for (const item of clientItems) {
        if (!item.id || !item.mediaId || !item.title) continue;
        upsert.run(
          userId,
          item.id,
          item.mediaId,
          item.mediaType || 'movie',
          item.title,
          item.poster_path ?? null,
          item.backdrop_path ?? null,
          item.progress ?? 0,
          item.currentTime ?? 0,
          item.duration ?? 0,
          item.streamId ?? null,
          item.streamUrl ?? null,
          item.magnetURI ?? null,
          item.fileIdx ?? null,
          item.lastWatched ?? Date.now(),
          item.season ?? null,
          item.episode ?? null
        );
      }
    });

    runSync(req.user.id, items);

    // Return the full merged history back to client
    const rows = db
      .prepare(
        `SELECT watch_id, media_id, media_type, title, poster_path, backdrop_path,
                progress, current_time, duration, stream_id, stream_url,
                magnet_uri, file_idx, last_watched, season, episode
         FROM watch_history
         WHERE user_id = ?
         ORDER BY last_watched DESC
         LIMIT 100`
      )
      .all(req.user.id);

    const merged = rows.map((row) => ({
      id: row.watch_id,
      mediaId: row.media_id,
      mediaType: row.media_type,
      title: row.title,
      poster_path: row.poster_path,
      backdrop_path: row.backdrop_path,
      progress: row.progress,
      currentTime: row.current_time,
      duration: row.duration,
      streamId: row.stream_id,
      streamUrl: row.stream_url,
      magnetURI: row.magnet_uri,
      fileIdx: row.file_idx,
      lastWatched: row.last_watched,
      season: row.season,
      episode: row.episode,
    }));

    res.json({ success: true, items: merged });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
