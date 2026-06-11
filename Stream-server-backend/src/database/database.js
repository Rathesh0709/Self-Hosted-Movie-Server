import path from 'path';
import fs from 'fs';
import Database from 'better-sqlite3';

const dataDir = path.resolve(process.cwd(), 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, 'streamflix.db');
export const db = new Database(dbPath);

db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    vote_average REAL DEFAULT 0,
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(user_id, media_id, media_type)
  );
`);

const favoriteColumns = db.prepare(`PRAGMA table_info(favorites)`).all();
const hasCategoryColumn = favoriteColumns.some((col) => col.name === 'category');
if (!hasCategoryColumn) {
  db.exec(`ALTER TABLE favorites ADD COLUMN category TEXT`);
}

db.exec(`
  CREATE TABLE IF NOT EXISTS watch_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    watch_id TEXT NOT NULL,
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    progress REAL DEFAULT 0,
    current_time REAL DEFAULT 0,
    duration REAL DEFAULT 0,
    stream_id TEXT,
    stream_url TEXT,
    magnet_uri TEXT,
    file_idx INTEGER,
    last_watched INTEGER NOT NULL,
    season INTEGER,
    episode INTEGER,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(user_id, watch_id)
  );
`);

export default db;
