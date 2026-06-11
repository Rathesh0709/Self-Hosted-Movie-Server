import express from 'express';
import zlib from 'zlib';

const router = express.Router();

/**
 * Basic SRT to VTT converter function
 */
function srt2vtt(srt) {
  let vtt = 'WEBVTT\n\n';
  vtt += srt
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    // Replace comma with dot in timestamps (00:00:01,000 --> 00:00:01.000)
    .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
    // Remove empty lines between WEBVTT and first cue if any issues arise, though standard allows it.
  return vtt;
}

// ────────────────────────────────────────────────────────────────
// GET /subtitles/search?imdbId=tt0816692  OR ?query=MovieTitle
// ────────────────────────────────────────────────────────────────
router.get('/search', async (req, res) => {
  try {
    let { imdbId, query, season, episode } = req.query;
    if (!imdbId && !query) return res.status(400).json({ error: 'imdbId or query required' });

    const hasEp = season !== undefined && episode !== undefined;

    let apiUrl = '';
    if (imdbId) {
      // OpenSubtitles expects imdbId without the 'tt' prefix
      imdbId = imdbId.replace(/^tt/, '');
      // For a TV episode, scope the search to that exact season+episode so we
      // don't get subtitles for random other episodes of the show.
      apiUrl = hasEp
        ? `https://rest.opensubtitles.org/search/episode-${parseInt(episode, 10)}/imdbid-${imdbId}/season-${parseInt(season, 10)}/sublanguageid-eng`
        : `https://rest.opensubtitles.org/search/imdbid-${imdbId}/sublanguageid-eng`;
    } else if (query) {
      // CRITICAL FIX: OpenSubtitles API redirects to a broken URL (https://_/) if the query contains uppercase letters!
      const safeQuery = query.toLowerCase();
      apiUrl = hasEp
        ? `https://rest.opensubtitles.org/search/episode-${parseInt(episode, 10)}/query-${encodeURIComponent(safeQuery)}/season-${parseInt(season, 10)}/sublanguageid-eng`
        : `https://rest.opensubtitles.org/search/query-${encodeURIComponent(safeQuery)}/sublanguageid-eng`;
    }
    const response = await fetch(apiUrl, {
      headers: {
        'User-Agent': 'TemporaryUserAgent'
      }
    });

    if (!response.ok) {
      throw new Error(`OpenSubtitles API responded with ${response.status}`);
    }

    const data = await response.json();
    
    // Return top 15 results
    const results = (Array.isArray(data) ? data : []).slice(0, 15).map(sub => ({
      id: sub.IDSubtitleFile,
      name: sub.SubFileName,
      rating: sub.SubRating,
      downloads: sub.SubDownloadsCnt,
      downloadLink: sub.SubDownloadLink, // This points to a .gz file
      format: sub.SubFormat
    }));

    res.json({ success: true, subtitles: results });
  } catch (err) {
    console.error('Subtitle search error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ────────────────────────────────────────────────────────────────
// GET /subtitles/download?url=...
// ────────────────────────────────────────────────────────────────
router.get('/download', async (req, res) => {
  try {
    const { url } = req.query;
    if (!url) return res.status(400).json({ error: 'url required' });

    const response = await fetch(url, {
      headers: {
        'User-Agent': 'TemporaryUserAgent'
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch subtitle from source: ${response.status}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // OpenSubtitles SubDownloadLink is generally GZipped.
    zlib.gunzip(buffer, (err, decompressed) => {
      if (err) {
        // If it fails to decompress, maybe it's not gzipped (fallback)
        serveSubtitle(buffer.toString('utf-8'), res);
        return;
      }
      serveSubtitle(decompressed.toString('utf-8'), res);
    });

  } catch (err) {
    console.error('Subtitle download error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

function serveSubtitle(content, res) {
  // Try to convert to VTT if it looks like SRT
  let finalContent = content;
  if (!content.startsWith('WEBVTT')) {
    finalContent = srt2vtt(content);
  }

  // Allow CORS so the video player can load the track
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
  res.send(finalContent);
}

export default router;
