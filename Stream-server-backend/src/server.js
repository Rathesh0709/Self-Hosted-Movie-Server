import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

import streamRoutes from './routes/streamRoutes.js';
import authRoutes from './routes/authRoutes.js';
import favoritesRoutes from './routes/favoritesRoutes.js';
import watchHistoryRoutes from './routes/watchHistoryRoutes.js';
import subtitleRoutes from './routes/subtitleRoutes.js';
import indexerRoutes from './routes/indexerRoutes.js';
import powerRoutes from './routes/powerRoutes.js';
import { activityTracker } from './middleware/activityMiddleware.js';
import { powerManager } from './power/powerManager.js';
import { StartupRecovery } from './power/startupRecovery.js';
import './database/database.js';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// Targeted request logging for Android playback debugging
app.use((req, res, next) => {
  if (req.path.startsWith('/api/hls/') || req.path.startsWith('/api/stream/')) {
    const range = req.headers.range;
    const origin = req.headers.origin;
    const ua = req.headers['user-agent'];
    console.log(
      `[REQ] ${req.method} ${req.originalUrl}` +
        (range ? ` range=${range}` : '') +
        (origin ? ` origin=${origin}` : '') +
        (ua ? ` ua=${ua}` : '')
    );
    res.on('finish', () => {
      console.log(`[RES] ${req.method} ${req.originalUrl} -> ${res.statusCode}`);
    });
  }
  next();
});

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'Accept',
    'User-Agent',
    'Origin',
    'X-Requested-With',
    'Range',
    'Content-Range',
    'Accept-Encoding',
    'Cache-Control',
    'Pragma',
    'ngrok-skip-browser-warning',
  ],
  exposedHeaders: ['Content-Length', 'Content-Range', 'Accept-Ranges'],
}));
// Express v5 path-to-regexp rejects '*' string routes; use regex for "all paths".
app.options(/.*/, cors());
app.use(express.json());
app.use(activityTracker(powerManager));

app.use('/api', streamRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/favorites', favoritesRoutes);
app.use('/api/watch-history', watchHistoryRoutes);
app.use('/api/subtitles', subtitleRoutes);
app.use('/api/indexers', indexerRoutes);
app.use('/api/power', powerRoutes);

app.use(
  '/hls',
  express.static(path.join(process.env.CACHE_PATH, 'hls'))
);

const PORT = process.env.PORT || 3000;

const recovery = new StartupRecovery();
recovery.recover().then(() => {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
  });
}).catch(err => {
  console.error('Startup recovery failed, starting server anyway:', err);
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
  });
});