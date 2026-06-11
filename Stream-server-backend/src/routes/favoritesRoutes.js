import express from 'express';
import db from '../database/database.js';
import { requireAuth } from '../middleware/authMiddleware.js';

const router = express.Router();
router.use(requireAuth);

router.get('/', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT media_id, media_type, category, title, poster_path, backdrop_path, vote_average, added_at
         FROM favorites
         WHERE user_id = ?
         ORDER BY added_at DESC`
      )
      .all(req.user.id);
    res.json({ success: true, items: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/', (req, res) => {
  const { media_id, media_type, category, title, poster_path, backdrop_path, vote_average } = req.body ?? {};
  if (!media_id || !media_type || !title) {
    return res.status(400).json({ success: false, error: 'media_id, media_type, title are required' });
  }
  try {
    db.prepare(
      `INSERT OR REPLACE INTO favorites
      (user_id, media_id, media_type, category, title, poster_path, backdrop_path, vote_average)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(req.user.id, media_id, media_type, category ?? null, title, poster_path ?? null, backdrop_path ?? null, vote_average ?? 0);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.delete('/:mediaId/:mediaType', (req, res) => {
  const { mediaId, mediaType } = req.params;
  try {
    db.prepare('DELETE FROM favorites WHERE user_id = ? AND media_id = ? AND media_type = ?')
      .run(req.user.id, mediaId, mediaType);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/check/:mediaId/:mediaType', (req, res) => {
  const { mediaId, mediaType } = req.params;
  try {
    const row = db
      .prepare('SELECT 1 FROM favorites WHERE user_id = ? AND media_id = ? AND media_type = ? LIMIT 1')
      .get(req.user.id, mediaId, mediaType);
    res.json({ success: true, isFavorite: Boolean(row) });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
