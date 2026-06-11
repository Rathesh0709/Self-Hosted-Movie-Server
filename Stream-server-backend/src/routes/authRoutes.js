import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import db from '../database/database.js';
import { requireAuth } from '../middleware/authMiddleware.js';

const router = express.Router();

function signToken(user) {
  return jwt.sign(
    { id: user.id, email: user.email },
    process.env.JWT_SECRET,
    { expiresIn: '30d' }
  );
}

router.post('/register', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password || password.length < 6) {
    return res.status(400).json({ success: false, error: 'Valid email and password(min 6) required' });
  }

  try {
    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
    if (existing) {
      return res.status(409).json({ success: false, error: 'Email already exists' });
    }

    const hash = await bcrypt.hash(password, 10);
    const insert = db.prepare('INSERT INTO users (email, password_hash) VALUES (?, ?)');
    const result = insert.run(email, hash);
    const user = { id: Number(result.lastInsertRowid), email };
    const token = signToken(user);
    return res.json({ success: true, token, user });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ success: false, error: 'Email and password required' });
  }

  try {
    const user = db.prepare('SELECT id, email, password_hash FROM users WHERE email = ?').get(email);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }
    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }
    const token = signToken(user);
    return res.json({ success: true, token, user: { id: user.id, email: user.email } });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/me', requireAuth, (req, res) => {
  res.json({ success: true, user: req.user });
});

router.put('/change-password', requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = req.body ?? {};
  if (!currentPassword || !newPassword || newPassword.length < 6) {
    return res.status(400).json({ success: false, error: 'Valid currentPassword/newPassword required' });
  }
  try {
    const user = db.prepare('SELECT id, password_hash FROM users WHERE id = ?').get(req.user.id);
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    const match = await bcrypt.compare(currentPassword, user.password_hash);
    if (!match) return res.status(401).json({ success: false, error: 'Current password is incorrect' });

    const newHash = await bcrypt.hash(newPassword, 10);
    db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(newHash, req.user.id);
    return res.json({ success: true, message: 'Password updated' });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
