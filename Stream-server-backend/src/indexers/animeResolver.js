import WebTorrent from "webtorrent";

function findEpisodeFile(files, episode) {
  const episodeStr = String(episode).padStart(4, "0");
  const patterns = [
    new RegExp(`\\b${episode}\\b`, "i"),
    new RegExp(`\\b0${episode}\\b`, "i"),
    new RegExp(`\\b00${episode}\\b`, "i"),
    new RegExp(`\\b000${episode}\\b`, "i"),
    new RegExp(`[- _.]${episodeStr}[- _.]`, "i"),
    new RegExp(`episode[ _.]?${episode}`, "i"),
    new RegExp(`ep[ _.]?${episode}`, "i"),
  ];

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    for (const pattern of patterns) {
      if (pattern.test(file.name)) {
        return { fileIdx: i, fileName: file.name, length: file.length };
      }
    }
  }
  return null;
}

export async function resolveAnimeEpisode(magnetURI, episode) {
  return new Promise((resolve, reject) => {
    const client = new WebTorrent({ maxConns: 50 });

    console.log(`[AnimeResolver] Resolving episode ${episode} for magnet: ${magnetURI.substring(0, 50)}...`);

    const timeout = setTimeout(() => {
      client.destroy();
      reject(new Error("Timeout resolving anime episode metadata"));
    }, 45000); // 45 seconds timeout

    client.add(magnetURI, { deselect: true }, torrent => {
      clearTimeout(timeout);

      // We only need the file list from the metadata — make sure NOTHING is
      // selected for download while we scan, otherwise WebTorrent starts
      // pulling random episodes from the batch before we've even picked one.
      try {
        torrent.deselect(0, torrent.pieces.length - 1, false);
        torrent.files.forEach(f => f.deselect());
      } catch (e) {}

      const match = findEpisodeFile(torrent.files, episode);
      
      if (!match) {
        client.destroy();
        return reject(new Error(`Episode ${episode} not found in torrent`));
      }

      console.log(`[AnimeResolver] Found episode ${episode} at index ${match.fileIdx} (${match.fileName})`);
      
      const result = {
        infoHash: torrent.infoHash,
        fileIdx: match.fileIdx,
        fileName: match.fileName,
      };

      client.destroy();
      resolve(result);
    });

    client.on("error", err => {
      clearTimeout(timeout);
      client.destroy();
      reject(err);
    });
  });
}
