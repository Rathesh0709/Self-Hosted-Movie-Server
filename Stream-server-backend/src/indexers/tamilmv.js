import { chromium } from "playwright";

function normalize(text) {
  return text.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function extractInfoHash(magnet) {
  const match = magnet.match(/urn:btih:([a-zA-Z0-9]+)/i);
  return match ? match[1].toLowerCase() : null;
}

export async function searchTamilMv(movieName, year = null) {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    console.log(`[TamilMV] Searching: ${movieName} (${year || 'Any'})`);

    const searchUrl = `https://www.1tamilmv.cards/index.php?/search/&q=${encodeURIComponent(movieName)}`;
    await page.goto(searchUrl, { waitUntil: "networkidle", timeout: 60000 });

    const topics = await page.$$eval('a[href*="/forums/topic/"]', elements =>
      elements.map(el => ({ title: el.textContent.trim(), href: el.href }))
    );

    const normalizedMovie = normalize(movieName);
    
    // Filter and score
    const filtered = topics
      .filter(item => {
        const title = item.title.toLowerCase();
        const normalizedTitle = normalize(title);
        if (!normalizedTitle.includes(normalizedMovie)) return false;
        if (title === "languages") return false;
        return true;
      })
      .map(item => {
        const title = item.title.toLowerCase();
        const normalizedTitle = normalize(title);
        let score = 0;
        
        if (normalizedTitle.startsWith(normalizedMovie)) score += 100;
        if (year && title.includes(`(${year})`)) score += 1000;
        if (normalizedTitle.includes(normalizedMovie + "2")) score -= 500;
        if (/1080p|720p|web-dl|hdrip|bluray|predvd|x264|x265|hevc/i.test(title)) score += 50;
        if (/gdrive|google drive/i.test(title)) score -= 1000;

        return {
          ...item,
          score,
          href: item.href.replace(/&do=findComment.*/, "")
        };
      })
      .sort((a, b) => b.score - a.score);

    // Limit to top 3 topics to avoid slow magnet extraction
    const topTopics = filtered.slice(0, 3);
    const results = [];

    for (const topic of topTopics) {
      console.log(`[TamilMV] Extracting magnets for topic: ${topic.title}`);
      try {
        await page.goto(topic.href, { waitUntil: "networkidle", timeout: 60000 });
        const magnets = await page.$$eval('a', elements =>
          elements
            .map(el => el.href)
            .filter(href => href && href.startsWith("magnet:?xt=urn:btih:"))
        );
        
        if (magnets.length > 0) {
          results.push({ topic: topic.title, magnets, score: topic.score });
        }
      } catch (e) {
        console.error(`[TamilMV] Failed to load topic: ${topic.title}`);
      }
    }

    const streams = [];
    const seenHashes = new Set();
    for (const result of results) {
      for (const magnet of result.magnets) {
        const infoHash = extractInfoHash(magnet);
        if (infoHash && !seenHashes.has(infoHash)) {
          seenHashes.add(infoHash);
          streams.push({
            infoHash,
            title: result.topic,
            quality: /1080p/i.test(result.topic) ? '1080p' : /720p/i.test(result.topic) ? '720p' : 'HDRip',
            size: 'Unknown Size',
            seeders: '0', 
            source: 'TamilMV',
            codec: /hevc|x265/i.test(result.topic) ? 'x265' : 'x264',
            magnetUrl: magnet
          });
        }
      }
    }

    return streams;

  } catch (err) {
    console.error('[TamilMV] Search Error:', err);
    return [];
  } finally {
    if (browser) await browser.close();
  }
}
