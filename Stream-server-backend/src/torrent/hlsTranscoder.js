import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

// Explicitly set ffmpeg/ffprobe paths from env, falling back to PATH lookup
if (process.env.FFMPEG_PATH) {
  ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
}
if (process.env.FFPROBE_PATH) {
  ffmpeg.setFfprobePath(process.env.FFPROBE_PATH);
}

// ─── Caches ──────────────────────────────────────────────────────
// Store active ffmpeg processes so we can kill them when a new seek happens
const activeProcesses = new Map();

// Duration cache: streamId → durationSeconds
const durationCache = new Map();

// In-flight segment locks: "streamId/seg_N" → Promise
const inflightSegments = new Map();

// Maximum concurrent transcode limit
let currentTranscodes = 0;
const MAX_TRANSCODES = 3;

// Segment cache directory
const SEGMENT_CACHE_DIR = path.join(process.env.CACHE_PATH || './cache', '.hls-segments');

// Ensure cache dir exists
if (!fs.existsSync(SEGMENT_CACHE_DIR)) {
  fs.mkdirSync(SEGMENT_CACHE_DIR, { recursive: true });
}

const SEGMENT_DURATION = 10; // seconds per segment

// ─── Helpers ─────────────────────────────────────────────────────

function applyMediaCors(res) {
  // `res.writeHead(...)` is used below and can override headers set by Express middleware.
  // Android WebView is strict about CORS for HLS playlist/segment fetches.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Origin, X-Requested-With, Content-Type, Accept, Authorization, Range, Content-Range, Accept-Encoding, Cache-Control, Pragma, ngrok-skip-browser-warning'
  );
  res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
}

function getSegmentCachePath(streamId, segmentIndex) {
  const streamDir = path.join(SEGMENT_CACHE_DIR, streamId);
  if (!fs.existsSync(streamDir)) {
    fs.mkdirSync(streamDir, { recursive: true });
  }
  return path.join(streamDir, `segment_${segmentIndex}.ts`);
}

function getVideoFileInput(videoFile, streamId) {
  if (typeof videoFile === 'string') {
    return { input: videoFile, isLocal: true };
  }

  if (videoFile.isLocal && videoFile.localPath) {
    return { input: videoFile.localPath, isLocal: true };
  }

  // It's a WebTorrent file object. Check if it's fully downloaded on disk.
  const parentTorrent = videoFile._torrent || videoFile.torrent;
  if (parentTorrent && parentTorrent.path) {
    const absolutePath = path.join(parentTorrent.path, videoFile.path);
    const isFullyDownloaded = videoFile.progress === 1 || videoFile.downloaded === videoFile.length;
    if (isFullyDownloaded && fs.existsSync(absolutePath)) {
      return { input: absolutePath, isLocal: true };
    }
  }

  // File is streaming. Instead of a ReadStream, we provide the internal HTTP stream URL
  // This allows ffmpeg to use HTTP Range requests for instant seeking!
  const port = process.env.PORT || 3000;
  const url = `http://127.0.0.1:${port}/api/stream/${streamId}?internal=1`;
  return { input: url, isLocal: false };
}

// ─── Public API ──────────────────────────────────────────────────

/**
 * Generate a static VOD m3u8 playlist based on duration
 */
export async function generateVODPlaylist(durationSeconds) {
  const totalSegments = Math.ceil(durationSeconds / SEGMENT_DURATION);

  let m3u8 = `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:${SEGMENT_DURATION}
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
`;

  for (let i = 0; i < totalSegments; i++) {
    const isLast = i === totalSegments - 1;
    const dur = isLast
      ? (durationSeconds - i * SEGMENT_DURATION).toFixed(6)
      : SEGMENT_DURATION.toFixed(6);
    m3u8 += `#EXTINF:${dur},\nsegment_${i}.ts\n`;
  }

  m3u8 += '#EXT-X-ENDLIST\n';
  return m3u8;
}

/**
 * Probe duration — cached per streamId so ffprobe only runs once.
 */
export function probeDuration(videoFile, streamId) {
  // Return cached duration if available
  if (streamId && durationCache.has(streamId)) {
    const cached = durationCache.get(streamId);
    console.log(`[HLS] Duration cache hit for ${streamId}: ${cached}s`);
    return Promise.resolve(cached);
  }

  return new Promise((resolve) => {
    const { input, isLocal } = getVideoFileInput(videoFile, streamId);

    ffmpeg.ffprobe(input, (err, metadata) => {
      if (!isLocal && input && typeof input.destroy === 'function') {
        try { input.destroy(); } catch (e) {}
      }

      let duration = 10800; // fallback: 3 hours
      if (!err && metadata?.format?.duration) {
        duration = parseFloat(metadata.format.duration);
      } else if (err) {
        console.error('[HLS] FFProbe error:', err.message);
      }

      // Cache it
      if (streamId) {
        durationCache.set(streamId, duration);
      }
      resolve(duration);
    });
  });
}

/**
 * Stream a specific HLS segment.
 * Serves from disk cache if available, otherwise transcodes and caches.
 */
export function streamHLSSegment(streamId, videoFile, segmentIndex, req, res) {
  const startTime = segmentIndex * SEGMENT_DURATION;
  const cachePath = getSegmentCachePath(streamId, segmentIndex);

  // ── 1. Serve from disk cache (instant) ─────────────────────────
  if (fs.existsSync(cachePath)) {
    const stat = fs.statSync(cachePath);
    if (stat.size > 0) {
      console.log(`[HLS] Cache HIT segment ${segmentIndex} for ${streamId}`);
      applyMediaCors(res);
      res.writeHead(200, {
        'Content-Type': 'video/MP2T',
        'Content-Length': stat.size,
        'Cache-Control': 'public, max-age=31536000, immutable',
      });
      fs.createReadStream(cachePath).pipe(res);
      return;
    }
  }

  // ── 2. Check if another request is already transcoding this segment
  const inflightKey = `${streamId}/seg_${segmentIndex}`;
  if (inflightSegments.has(inflightKey)) {
    // Wait for the in-flight transcode to finish, then serve from cache
    console.log(`[HLS] Waiting for in-flight segment ${segmentIndex}...`);
    inflightSegments.get(inflightKey).then(() => {
      if (fs.existsSync(cachePath) && fs.statSync(cachePath).size > 0) {
        const stat = fs.statSync(cachePath);
        applyMediaCors(res);
        res.writeHead(200, {
          'Content-Type': 'video/MP2T',
          'Content-Length': stat.size,
          'Cache-Control': 'public, max-age=31536000, immutable',
        });
        fs.createReadStream(cachePath).pipe(res);
      } else {
        res.sendStatus(500);
      }
    }).catch(() => res.sendStatus(500));
    return;
  }

  // ── 3. Transcode, write to disk + stream to response simultaneously
  console.log(`[HLS] Transcoding segment ${segmentIndex} (${startTime}s) for ${streamId}`);

  applyMediaCors(res);
  res.writeHead(200, {
    'Content-Type': 'video/MP2T',
    'Cache-Control': 'public, max-age=31536000, immutable',
    'Connection': 'keep-alive',
  });

  const { input, isLocal } = getVideoFileInput(videoFile, streamId);

  // Create a write stream to cache the segment on disk
  const cacheWriteStream = fs.createWriteStream(cachePath);
  let cacheWriteOk = true;
  cacheWriteStream.on('error', () => { cacheWriteOk = false; });

  // Build the resolve/reject for the inflight promise
  let resolveInflight, rejectInflight;
  const inflightPromise = new Promise((res, rej) => {
    resolveInflight = res;
    rejectInflight = rej;
  });
  // Add empty catch to prevent unhandled promise rejections if it rejects before being awaited
  inflightPromise.catch(() => {});
  inflightSegments.set(inflightKey, inflightPromise);

  const command = ffmpeg(input)
    .inputOptions([`-ss ${startTime}`])
    .videoCodec('libx264')
    .audioCodec('aac')
    .audioChannels(2)
    .outputOptions([
      '-preset ultrafast',
      '-tune zerolatency',
      '-crf 26', // slightly higher CRF for faster encoding
      `-t ${SEGMENT_DURATION}`,
      '-start_at_zero',
      `-output_ts_offset ${startTime}`,
      '-map 0:v:0',
      '-map 0:a:0?',
      '-muxdelay 0',
      '-vf scale=-2:720', // Downscale to 720p to prevent CPU bottleneck and buffering
      '-f mpegts',
      '-pix_fmt yuv420p',
      '-flags +cgop',
      '-g 48',
    ])
    .on('start', (cmdLine) => {
      // console.log('[HLS] FFmpeg:', cmdLine);
    })
    .on('error', (err) => {
      if (err.message && !err.message.includes('Output stream closed') && !err.message.includes('SIGKILL')) {
        console.error('[HLS] FFmpeg error:', err.message);
      }
      try { cacheWriteStream.destroy(); } catch (e) {}
      // Remove partial cache file
      try { if (fs.existsSync(cachePath)) fs.unlinkSync(cachePath); } catch (e) {}
      inflightSegments.delete(inflightKey);
      rejectInflight?.();
      // Add timeout to inflight promise to avoid hanging forever
      setTimeout(() => {
        if (inflightSegments.has(inflightKey)) {
           rejectInflight?.(new Error('Transcode timeout'));
           inflightSegments.delete(inflightKey);
           try { command.kill('SIGKILL'); } catch (e) {}
        }
      }, 30000);
    })
    .on('end', () => {
      currentTranscodes--;
      try { cacheWriteStream.end(); } catch (e) {}
      activeProcesses.delete(inflightKey);
      inflightSegments.delete(inflightKey);
      resolveInflight?.();
      console.log(`[HLS] Segment ${segmentIndex} cached for ${streamId}`);
    });

  currentTranscodes++;
  activeProcesses.set(inflightKey, command);

  let closed = false;
  const cleanup = () => {
    if (closed) return;
    closed = true;
    try { command.kill('SIGKILL'); } catch (e) {}
    if (!isLocal && input && typeof input.destroy === 'function') {
      try { input.destroy(); } catch (e) {}
    }
    if (activeProcesses.get(inflightKey) === command) {
      activeProcesses.delete(inflightKey);
    }
  };

  res.on('close', () => {
    // Don't kill ffmpeg if it's still writing to cache — let it finish
    // Only kill if the response was closed prematurely (before ffmpeg finished)
    if (!cacheWriteOk) cleanup();
  });
  if (req) {
    req.on('close', () => {
      // Same: let ffmpeg finish writing to cache even if client disconnected
    });
  }

  // Pipe ffmpeg output to BOTH the response AND the disk cache
  const ffmpegStream = command.pipe();
  ffmpegStream.on('data', (chunk) => {
    try { res.write(chunk); } catch (e) {}
    try { if (cacheWriteOk) cacheWriteStream.write(chunk); } catch (e) {}
  });
  ffmpegStream.on('end', () => {
    try { res.end(); } catch (e) {}
  });
  ffmpegStream.on('error', () => {});

  // Also pre-transcode the NEXT segment in background for smooth playback
  prefetchNextSegment(streamId, videoFile, segmentIndex + 1);
}

/**
 * Pre-transcode the next segment in the background for seamless playback.
 */
function prefetchNextSegment(streamId, videoFile, nextSegmentIndex) {
  const nextCachePath = getSegmentCachePath(streamId, nextSegmentIndex);
  const inflightKey = `${streamId}/seg_${nextSegmentIndex}`;

  // Skip if already cached or already in-flight
  if (fs.existsSync(nextCachePath) && fs.statSync(nextCachePath).size > 0) return;
  if (inflightSegments.has(inflightKey)) return;

  // Check duration cache to avoid transcoding beyond the video
  const cachedDuration = durationCache.get(streamId);
  if (cachedDuration && nextSegmentIndex * SEGMENT_DURATION >= cachedDuration) return;

  const startTime = nextSegmentIndex * SEGMENT_DURATION;
  console.log(`[HLS] Prefetching segment ${nextSegmentIndex} for ${streamId}`);

  const { input, isLocal } = getVideoFileInput(videoFile, streamId);
  const cacheWriteStream = fs.createWriteStream(nextCachePath);
  let cacheOk = true;
  cacheWriteStream.on('error', () => { cacheOk = false; });

  let resolveInflight, rejectInflight;
  const inflightPromise = new Promise((res, rej) => { 
    resolveInflight = res; 
    rejectInflight = rej;
  });
  inflightPromise.catch(() => {});
  inflightSegments.set(inflightKey, inflightPromise);

  const command = ffmpeg(input)
    .inputOptions([`-ss ${startTime}`])
    .videoCodec('libx264')
    .audioCodec('aac')
    .audioChannels(2)
    .outputOptions([
      '-preset ultrafast',
      '-tune zerolatency',
      '-crf 26',
      `-t ${SEGMENT_DURATION}`,
      '-start_at_zero',
      `-output_ts_offset ${startTime}`,
      '-map 0:v:0',
      '-map 0:a:0?',
      '-muxdelay 0',
      '-vf scale=-2:720', // Downscale to 720p to prevent CPU bottleneck and buffering
      '-f mpegts',
      '-pix_fmt yuv420p',
      '-flags +cgop',
      '-g 48',
    ])
    .on('error', (err) => {
      if (err.message && !err.message.includes('Output stream closed') && !err.message.includes('SIGKILL')) {
        console.error('[HLS] Prefetch error:', err.message);
      }
      try { cacheWriteStream.destroy(); } catch (e) {}
      try { if (fs.existsSync(nextCachePath)) fs.unlinkSync(nextCachePath); } catch (e) {}
      inflightSegments.delete(inflightKey);
      rejectInflight?.();
      setTimeout(() => {
        if (inflightSegments.has(inflightKey)) {
           rejectInflight?.(new Error('Prefetch timeout'));
           inflightSegments.delete(inflightKey);
           try { command.kill('SIGKILL'); } catch (e) {}
        }
      }, 30000);
    })
    .on('end', () => {
      currentTranscodes--;
      try { cacheWriteStream.end(); } catch (e) {}
      inflightSegments.delete(inflightKey);
      resolveInflight?.();
      console.log(`[HLS] Prefetched segment ${nextSegmentIndex} for ${streamId}`);
    });

  currentTranscodes++;
  command.pipe(cacheWriteStream, { end: true });
}

/**
 * Clean up cached segments for a stream (call on stream destroy)
 */
export function cleanupStreamCache(streamId) {
  const streamDir = path.join(SEGMENT_CACHE_DIR, streamId);
  if (fs.existsSync(streamDir)) {
    try {
      fs.rmSync(streamDir, { recursive: true, force: true });
      console.log(`[HLS] Cleaned cache for ${streamId}`);
    } catch (e) {}
  }
  durationCache.delete(streamId);
}