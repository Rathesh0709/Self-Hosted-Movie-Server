import express from 'express';
import crypto from 'crypto';
import path from 'path';
import fs from 'fs';
import ffmpeg from 'fluent-ffmpeg';
import dotenv from 'dotenv';

dotenv.config();

// Explicitly set ffmpeg/ffprobe paths from env
if (process.env.FFMPEG_PATH) {
  ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
}
if (process.env.FFPROBE_PATH) {
  ffmpeg.setFfprobePath(process.env.FFPROBE_PATH);
}

import { startTorrent } from '../torrent/torrentManager.js';
import { generateVODPlaylist, probeDuration, streamHLSSegment } from '../torrent/hlsTranscoder.js';
import { streamManager } from '../torrent/streamManager.js';
import { downloadManager } from '../torrent/downloadManager.js';

const router = express.Router();

const conversionJobs = new Map();

function applyMediaCors(res) {
  // Important: this file uses `res.writeHead(...)` for media responses.
  // `writeHead` can effectively override headers set earlier by global `cors()`.
  // Android WebView is stricter about CORS on media + range requests, so ensure
  // these headers are present on EVERY playlist/segment/byte-range response.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Origin, X-Requested-With, Content-Type, Accept, Authorization, Range, Content-Range, Accept-Encoding, Cache-Control, Pragma, ngrok-skip-browser-warning'
  );
  res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
}

// ────────────────────────────────────────────────────────────────
// Helper: detect whether a filename indicates HEVC/x265 encoding
// Torrent filenames almost always include codec info like
// "x265", "HEVC", "H.265", "H265", or "10bit".
// ────────────────────────────────────────────────────────────────
function isHEVC(fileName) {
  const lower = fileName.toLowerCase();
  return (
    lower.includes('x265') ||
    lower.includes('hevc') ||
    lower.includes('h265') ||
    lower.includes('h.265') ||
    lower.includes('10bit')
  );
}

async function ensureMp4Conversion(sourcePath, targetPath) {
  if (fs.existsSync(targetPath) && fs.statSync(targetPath).size > 0) {
    return targetPath;
  }

  if (conversionJobs.has(targetPath)) {
    return conversionJobs.get(targetPath);
  }

  const conversionPromise = new Promise((resolve, reject) => {
    ffmpeg(sourcePath)
      .videoCodec('libx264')
      .audioCodec('aac')
      .audioChannels(2)
      .outputOptions([
        '-preset veryfast',
        '-crf 22',
        '-movflags +faststart',
        '-pix_fmt yuv420p'
      ])
      .on('end', () => resolve(targetPath))
      .on('error', (err) => reject(err))
      .save(targetPath);
  });

  conversionJobs.set(targetPath, conversionPromise);
  try {
    const result = await conversionPromise;
    return result;
  } finally {
    conversionJobs.delete(targetPath);
  }
}

// ────────────────────────────────────────────────────────────────
// POST /stream/start  — initialize a torrent and return stream URL
// ────────────────────────────────────────────────────────────────
router.post('/stream/start', async (req, res) => {

  try {

    const { magnetURI, fileIdx } = req.body;

    if (!magnetURI) {
      return res.status(400).json({
        success: false,
        error: 'magnetURI required'
      });
    }

    console.log('Starting Torrent Stream...');

    const torrentData = await startTorrent(magnetURI, fileIdx);

    const streamId =
      crypto.randomBytes(8).toString('hex');

    streamManager.registerStream(streamId, torrentData);

    console.log(
      `Stream Created: ${streamId}`
    );

    // If it's an AVI, MKV, or HEVC file, route to On-Demand HLS Transcoder
    if (isHEVC(torrentData.videoFile.name) || torrentData.videoFile.name.toLowerCase().endsWith('.avi') || torrentData.videoFile.name.toLowerCase().endsWith('.mkv')) {
      console.log('AVI/MKV/HEVC file detected. Routing to On-Demand HLS Transcoder...');
      return res.json({
        success: true,
        streamId,
        stream: `/api/hls/${streamId}/index.m3u8`
      });
    }

    res.json({
      success: true,
      streamId,
      stream: `/api/stream/${streamId}`
    });

  } catch (err) {

    console.error(err);

    res.status(500).json({
      success: false,
      error: err.message
    });
  }

});

// ────────────────────────────────────────────────────────────────
// POST /stream/download  — add torrent to server downloads
// ────────────────────────────────────────────────────────────────
router.post('/stream/download', async (req, res) => {
  try {
    const { magnetURI, fileIdx } = req.body;
    if (!magnetURI) {
      return res.status(400).json({ success: false, error: 'magnetURI required' });
    }

    const response = await downloadManager.addDownload(magnetURI, fileIdx);
    return res.json(response);

  } catch (err) {
    console.error('Download request error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// POST /stream/file/start — create a stream session for local file
// ────────────────────────────────────────────────────────────────
router.post('/stream/file/start', async (req, res) => {
  try {
    const { filePath } = req.body ?? {};
    if (!filePath) {
      return res.status(400).json({ success: false, error: 'filePath required' });
    }

    const cachePath = process.env.CACHE_PATH;
    if (!cachePath) {
      return res.status(500).json({ success: false, error: 'CACHE_PATH not configured' });
    }

    const resolvedFilePath = path.resolve(cachePath, filePath);
    if (!resolvedFilePath.startsWith(path.resolve(cachePath))) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }
    if (!fs.existsSync(resolvedFilePath) || !fs.statSync(resolvedFilePath).isFile()) {
      return res.status(404).json({ success: false, error: 'File not found' });
    }

    let finalFilePath = resolvedFilePath;
    let finalFileName = path.basename(finalFilePath);

    const stat = fs.statSync(finalFilePath);
    const streamId = crypto.randomBytes(8).toString('hex');
    const relativePath = path.relative(cachePath, finalFilePath).replace(/\\/g, '/');

    const videoFile = {
      name: finalFileName,
      path: relativePath,
      length: stat.size,
      createReadStream: (opts) => fs.createReadStream(finalFilePath, opts),
    };

    streamManager.registerStream(streamId, {
      torrent: { path: cachePath, name: finalFileName, done: true, progress: 1 },
      videoFile,
    });

    if (isHEVC(finalFileName) || finalFileName.toLowerCase().endsWith('.avi') || finalFileName.toLowerCase().endsWith('.mkv')) {
      return res.json({ success: true, streamId, stream: `/api/hls/${streamId}/index.m3u8` });
    }

    return res.json({ success: true, streamId, stream: `/api/stream/${streamId}` });


  } catch (err) {
    console.error('Local file stream start error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// GET /stream/downloads  — list active torrent download states
// ────────────────────────────────────────────────────────────────
router.get('/stream/downloads', (req, res) => {
  try {
    const items = downloadManager.getActiveDownloads();
    res.json({ success: true, items });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// GET /stream/:streamId/subtitles  — list subtitles in the torrent
// ────────────────────────────────────────────────────────────────
router.get('/stream/:streamId/subtitles', (req, res) => {
  try {
    const session = streamManager.getSession(req.params.streamId);
    if (!session || !session.torrentData || !session.torrentData.torrent || !session.torrentData.torrent.files) {
      return res.json({ success: true, subtitles: [] });
    }
    
    const streamData = session.torrentData;

    const subtitles = streamData.torrent.files
      .map((f, i) => ({ name: f.name, idx: i }))
      .filter(f => f.name.toLowerCase().endsWith('.srt') || f.name.toLowerCase().endsWith('.vtt'));

    res.json({ success: true, subtitles });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// GET /stream/:streamId/subtitle/:fileIdx  — get a subtitle file
// ────────────────────────────────────────────────────────────────
router.get('/stream/:streamId/subtitle/:fileIdx', async (req, res) => {
  try {
    const session = streamManager.getSession(req.params.streamId);
    if (!session || !session.torrentData || !session.torrentData.torrent || !session.torrentData.torrent.files) {
      return res.sendStatus(404);
    }
    
    const streamData = session.torrentData;

    const idx = parseInt(req.params.fileIdx, 10);
    const file = streamData.torrent.files[idx];
    if (!file) return res.sendStatus(404);

    applyMediaCors(res);
    res.setHeader('Content-Type', 'text/vtt; charset=utf-8');

    // Webtorrent file.getBuffer is useful for small files like subs
    file.getBuffer((err, buffer) => {
      if (err) {
        console.error('Subtitle buffer error:', err);
        return res.sendStatus(500);
      }
      
      const content = buffer.toString('utf-8');
      
      // Convert to VTT if it's an SRT file
      if (file.name.toLowerCase().endsWith('.srt')) {
        let vtt = 'WEBVTT\n\n';
        vtt += content
          .replace(/\r\n/g, '\n')
          .replace(/\r/g, '\n')
          .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
        res.send(vtt);
      } else {
        res.send(content);
      }
    });

  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// GET /stream/:streamId  — stream video bytes (with HEVC fallback)
// ────────────────────────────────────────────────────────────────
// Restrict streamId to generated 16-char hex IDs so /stream/files,
// /stream/downloads, etc. do not get captured by this handler.
router.get(/^\/stream\/([a-f0-9]{16})$/, async (req, res) => {

  try {

    const session = streamManager.getSession(req.params[0]);

    if (!session || !session.torrentData) {
      return res.sendStatus(404);
    }

    const streamData = session.torrentData;

    const file = streamData.videoFile;

    // HEVC and AVI are now handled by /api/hls/... routes.
    // If we reach here and it's HEVC, the client (fallback) used the wrong URL.
    // We should redirect them to the HLS playlist.
    if (!req.query.internal && (isHEVC(file.name) || file.name.toLowerCase().endsWith('.avi'))) {
      console.log('Client requested raw stream for HEVC/AVI. Redirecting to HLS playlist...');
      return res.redirect(`/api/hls/${req.params[0]}/index.m3u8`);
    }

    // ── Standard byte-range streaming for natively-supported formats ──
    const range = req.headers.range;

    if (!range) {
      // Some clients (notably Android WebView) may issue an initial request without Range.
      // Serving a full 200 response is more compatible than a 416 and still supports seeking.
      applyMediaCors(res);
      res.writeHead(200, {
        'Content-Length': file.length,
        'Content-Type': 'video/mp4',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      });
      const stream = streamManager.createRangeStream(req.params[0], 0, file.length - 1);
      let streamClosed = false;
      const cleanup = () => {
        if (streamClosed) return;
        streamClosed = true;
        try { stream.cleanup(); } catch {}
      };
      req.on('close', cleanup);
      res.on('close', cleanup);
      stream.on('error', () => {
        cleanup();
        if (!res.headersSent) res.sendStatus(500);
      });
      stream.pipe(res);
      return;
    }

    const positions =
      range.replace(/bytes=/, '').split('-');

    const start =
      parseInt(positions[0], 10);

    const total = file.length;

    const end = positions[1]
      ? parseInt(positions[1], 10)
      : total - 1;

    const chunkSize =
      (end - start) + 1;

    console.log(
      `Streaming Range: ${start}-${end}`
    );

    applyMediaCors(res);
    res.writeHead(206, {
      'Content-Range':
        `bytes ${start}-${end}/${total}`,

      'Accept-Ranges': 'bytes',

      'Content-Length': chunkSize,

      'Content-Type': 'video/mp4',

      'Cache-Control': 'no-cache'
    });

    const stream = streamManager.createRangeStream(req.params[0], start, end);

    let streamClosed = false;

    const cleanup = () => {
      if (streamClosed) return;
      streamClosed = true;
      console.log('Cleaning Stream');
      try { stream.cleanup(); } catch {}
    };

    req.on('close', () => {
      console.log('Request Closed');
      cleanup();
    });

    res.on('close', () => {
      console.log('Response Closed');
      cleanup();
    });

    stream.on('error', err => {
      console.error('Stream Error:', err.message);
      cleanup();
      if (!res.headersSent) {
        res.sendStatus(500);
      }
    });

    stream.pipe(res);

  } catch (err) {

    console.error(err);

    res.sendStatus(500);
  }

});

// ────────────────────────────────────────────────────────────────
// GET /hls/:streamId/index.m3u8  — Generate VOD Playlist
// ────────────────────────────────────────────────────────────────
router.get('/hls/:streamId/index.m3u8', async (req, res) => {
  try {
    const session = streamManager.getSession(req.params.streamId);
    if (!session || !session.torrentData) return res.sendStatus(404);
    
    const streamData = session.torrentData;

    const sid = req.params.streamId;
    console.log(`[HLS] Generating playlist for stream ${sid}...`);
    const duration = await probeDuration(streamData.videoFile, sid);
    console.log(`[HLS] Duration: ${duration}s`);
    
    const m3u8 = await generateVODPlaylist(duration);
    
    applyMediaCors(res);
    res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(m3u8);
  } catch (err) {
    console.error('HLS Playlist Error:', err);
    if (!res.headersSent) {
      applyMediaCors(res);
      res.status(500).json({
        success: false,
        error: 'HLS playlist generation failed',
        message: err?.message ?? String(err),
      });
    }
  }
});

// ────────────────────────────────────────────────────────────────
// GET /hls/:streamId/segment_:seq.ts  — Generate HLS Segment
// ────────────────────────────────────────────────────────────────
router.get('/hls/:streamId/segment_:seq.ts', (req, res) => {
  try {
    const session = streamManager.getSession(req.params.streamId);
    if (!session || !session.torrentData) return res.sendStatus(404);
    
    const streamData = session.torrentData;

    const seq = parseInt(req.params.seq, 10);
    applyMediaCors(res);
    streamHLSSegment(req.params.streamId, streamData.videoFile, seq, req, res);
  } catch (err) {
    console.error('HLS Segment Error:', err);
    res.sendStatus(500);
  }
});

// ────────────────────────────────────────────────────────────────
// GET /stream/file/*  — serve already-downloaded files from disk
// This allows playback of cached files even after a backend restart.
// The path is relative to CACHE_PATH.
// Example: /api/stream/file/some-torrent-folder/movie.mkv
// ────────────────────────────────────────────────────────────────
router.get(/^\/stream\/file\/(.*)$/, async (req, res) => {

  try {
    const cachePath = process.env.CACHE_PATH;
    if (!cachePath) {
      return res.status(500).json({ error: 'CACHE_PATH not configured' });
    }

    // Capture the wildcard matched path
    const relativePath = req.params[0];
    const filePath = path.resolve(cachePath, relativePath);

    // Security: ensure the resolved path is inside CACHE_PATH
    if (!filePath.startsWith(path.resolve(cachePath))) {
      return res.status(403).json({ error: 'Access denied' });
    }

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'File not found' });
    }

    const stat = fs.statSync(filePath);
    const total = stat.size;
    const fileName = path.basename(filePath);

    // If HEVC or AVI, transcode on-the-fly
    if (isHEVC(fileName) || fileName.toLowerCase().endsWith('.avi')) {
      console.log(`Serving cached HEVC file with transcoding: ${fileName}`);

      applyMediaCors(res);
      res.writeHead(200, {
        'Content-Type': 'video/mp4',
        'Cache-Control': 'no-cache',
        'Transfer-Encoding': 'chunked'
      });

      const command = ffmpeg(filePath)
        .videoCodec('libx264')
        .audioCodec('aac')
        .audioChannels(2)
        .outputOptions([
          '-preset ultrafast',
          '-crf 23',
          '-movflags frag_keyframe+empty_moov+faststart',
          '-f mp4',
          '-pix_fmt yuv420p'
        ])
        .on('error', err => {
          if (err.message && !err.message.includes('Output stream closed')) {
            console.error('FFmpeg file transcoding error:', err.message);
          }
        });

      let closed = false;
      const cleanup = () => {
        if (closed) return;
        closed = true;
        try { command.kill('SIGKILL'); } catch {}
      };

      req.on('close', () => cleanup());
      res.on('close', () => cleanup());

      command.pipe(res, { end: true });
      return;
    }

    // Standard byte-range serving from disk
    const range = req.headers.range;

    if (!range) {
      // No range header — serve the entire file
      applyMediaCors(res);
      res.writeHead(200, {
        'Content-Length': total,
        'Content-Type': 'video/mp4',
        'Accept-Ranges': 'bytes'
      });
      fs.createReadStream(filePath).pipe(res);
      return;
    }

    const positions = range.replace(/bytes=/, '').split('-');
    const start = parseInt(positions[0], 10);
    const end = positions[1] ? parseInt(positions[1], 10) : total - 1;
    const chunkSize = (end - start) + 1;

    console.log(`Serving cached file range: ${start}-${end} of ${fileName}`);

    applyMediaCors(res);
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${total}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Content-Type': 'video/mp4',
      'Cache-Control': 'no-cache'
    });

    fs.createReadStream(filePath, { start, end }).pipe(res);

  } catch (err) {
    console.error('File stream error:', err);
    if (!res.headersSent) {
      res.sendStatus(500);
    }
  }

});

// ────────────────────────────────────────────────────────────────
// GET /stream/files  — list all downloaded files in CACHE_PATH
// Returns a flat list of video files available for direct playback.
// ────────────────────────────────────────────────────────────────
router.get('/stream/files', (req, res) => {

  try {
    const cachePath = process.env.CACHE_PATH;
    if (!cachePath || !fs.existsSync(cachePath)) {
      return res.json({ success: true, files: [] });
    }

    const videoExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.ts', '.m2ts'];
    const skipFolderNames = new Set(['hls', '.hls-segments', 'hls-segments', '.converted']);
    const results = [];
    const seenPaths = new Set();

    function pushResult(fullPath, relPath, displayName) {
      if (seenPaths.has(relPath)) return;
      seenPaths.add(relPath);
      const stat = fs.statSync(fullPath);
      results.push({
        name: displayName ?? path.basename(fullPath),
        path: relPath.replace(/\\/g, '/'),
        size: stat.size,
        sizeMB: Math.round(stat.size / (1024 * 1024)),
        needsTranscode: isHEVC(path.basename(fullPath)) || path.extname(fullPath).toLowerCase() === '.avi' || path.extname(fullPath).toLowerCase() === '.mkv'
      });
    }

    function findLargestVideoFile(dir) {
      let best = null;
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          if (skipFolderNames.has(entry.name.toLowerCase())) continue;
          const nested = findLargestVideoFile(fullPath);
          if (nested && (!best || nested.size > best.size)) best = nested;
        } else if (entry.isFile()) {
          const ext = path.extname(entry.name).toLowerCase();
          if (videoExtensions.includes(ext)) {
            const stat = fs.statSync(fullPath);
            if (stat.size > 0 && (!best || stat.size > best.size)) {
              best = { fullPath, size: stat.size };
            }
          }
        }
      }
      return best;
    }

    function walkDir(dir, base) {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const relPath = path.join(base, entry.name);
        if (entry.isDirectory()) {
          if (skipFolderNames.has(entry.name.toLowerCase())) continue;
          const bestVideo = findLargestVideoFile(fullPath);
          if (bestVideo) {
            const bestRelPath = path.relative(cachePath, bestVideo.fullPath);
            pushResult(bestVideo.fullPath, bestRelPath, entry.name);
          }
          walkDir(fullPath, relPath);
        } else if (entry.isFile()) {
          const ext = path.extname(entry.name).toLowerCase();
          if (videoExtensions.includes(ext)) {
            pushResult(fullPath, relPath, entry.name);
          }
        }
      }
    }

    walkDir(cachePath, '');

    res.json({ success: true, files: results });

  } catch (err) {
    console.error('File listing error:', err);
    res.status(500).json({ success: false, error: err.message });
  }

});

router.get('/stream/status', (req, res) => {
  const status = streamManager.getGlobalStatus();
  res.json({
    success: true,
    activeStreams: status.activeStreams,
    bufferAheadSeconds: status.bufferAheadSeconds,
    downloadSpeed: status.downloadSpeed,
    torrentProgress: status.torrentProgress,
    health: status.health,
  });
});

router.get('/stream/:streamId/status', (req, res) => {
  const status = streamManager.getStreamHealth(req.params.streamId);
  if (!status) return res.sendStatus(404);
  res.json({ success: true, ...status });
});

router.post('/stream/:streamId/seek', (req, res) => {
  const { seekTime, byteOffset } = req.body;
  if (byteOffset !== undefined) {
    streamManager.handleSeek(req.params.streamId, byteOffset);
  }
  res.json({ success: true });
});

router.post('/stream/:streamId/playback-position', (req, res) => {
  const { byteOffset } = req.body;
  if (byteOffset !== undefined) {
    streamManager.reportPlaybackPosition(req.params.streamId, byteOffset);
  }
  res.json({ success: true });
});

router.delete('/stream/:streamId', (req, res) => {
  streamManager.cleanupStream(req.params.streamId);
  res.json({ success: true });
});

// ────────────────────────────────────────────────────────────────
// GET /health
// ────────────────────────────────────────────────────────────────
router.get('/health', (req, res) => {

  res.json({
    success: true,
    status: 'running'
  });

});

export default router;