import WebTorrent from 'webtorrent';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

const client = new WebTorrent({
  maxConns: 100
});

const activeTorrents = new Map();

client.on('error', err => {
  console.error('WebTorrent Error:', err.message);
});

export function startTorrent(magnetURI, fileIdx, streaming = true) {

  // If a request for this magnet is already in progress or completed, return its Promise/Data
  if (activeTorrents.has(magnetURI)) {
    console.log('Using Existing Torrent Data/Promise');
    // We can return the promise or the resolved data directly, because await handles both.
    return activeTorrents.get(magnetURI);
  }

  // 1. Try to parse display name (dn) from magnet URI to check local storage
  let dn = null;
  const dnMatch = magnetURI.match(/[&?]dn=([^&]+)/);
  if (dnMatch && dnMatch[1]) {
    dn = decodeURIComponent(dnMatch[1]);
  }

  const cachePath = process.env.CACHE_PATH;

  if (dn && cachePath) {
    let localFilePath = null;
    let relativeFilePath = null;
    let fileSize = 0;
    let matchedPath = null;
    const sanitizedDn = dn.replace(/[<>:"/\\|?*]/g, '');
    const possibleNames = [dn, sanitizedDn];
    const supportedExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v'];

    for (const name of possibleNames) {
      if (!name) continue;
      const exactPath = path.join(cachePath, name);
      if (fs.existsSync(exactPath)) {
        matchedPath = exactPath;
        break;
      }
      for (const ext of supportedExtensions) {
        if (fs.existsSync(exactPath + ext)) {
          matchedPath = exactPath + ext;
          break;
        }
      }
      if (matchedPath) break;
    }

    // 4. Fuzzy match if exact matches fail (Torrentio often truncates or removes symbols like parenthesis)
    if (!matchedPath && fs.existsSync(cachePath)) {
      const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
      const n2 = normalize(dn);
      
      if (n2.length > 5) { // Prevent tiny strings from false matching
        const items = fs.readdirSync(cachePath);
        let bestMatch = null;
        let bestDiff = Infinity;

        for (const item of items) {
          const itemPath = path.join(cachePath, item);
          let itemName = item;
          
          try {
            if (fs.statSync(itemPath).isFile()) {
              itemName = item.replace(/\.[^/.]+$/, '');
            }
          } catch (e) {
            continue;
          }

          const n1 = normalize(itemName);
          if (n1.includes(n2) || n2.includes(n1)) {
            const diff = Math.abs(n1.length - n2.length);
            if (diff < bestDiff) {
              bestDiff = diff;
              bestMatch = item;
            }
          }
        }

        if (bestMatch) {
          matchedPath = path.join(cachePath, bestMatch);
          console.log(`[startTorrent] Fuzzy matched local storage: ${bestMatch} for dn: ${dn}`);
        }
      }
    }

    if (matchedPath) {
      const stat = fs.statSync(matchedPath);
      if (stat.isDirectory()) {
        const files = fs.readdirSync(matchedPath);
        const videoFiles = files.filter(f => {
          const ext = path.extname(f).toLowerCase();
          return supportedExtensions.includes(ext);
        }).map(f => {
          const fp = path.join(matchedPath, f);
          return {
            name: f,
            path: fp,
            size: fs.statSync(fp).size
          };
        });

        if (videoFiles.length > 0) {
          let selectedFile = null;
          if (fileIdx !== undefined && videoFiles[fileIdx]) {
            selectedFile = videoFiles[fileIdx];
          } else {
            // Sort by size descending
            selectedFile = videoFiles.sort((a, b) => b.size - a.size)[0];
          }
          if (selectedFile) {
            localFilePath = selectedFile.path;
            relativeFilePath = path.relative(cachePath, selectedFile.path);
            fileSize = selectedFile.size;
          }
        }
      } else if (stat.isFile()) {
        localFilePath = matchedPath;
        relativeFilePath = path.relative(cachePath, matchedPath);
        fileSize = stat.size;
      }
    }

    if (localFilePath) {
      console.log(`[startTorrent] Torrent files found locally on storage: ${localFilePath}`);
      const mockVideoFile = {
        name: path.basename(localFilePath),
        path: relativeFilePath.replace(/\\/g, '/'),
        length: fileSize,
        downloaded: fileSize,
        progress: 1,
        isLocal: true,
        localPath: localFilePath,
        createReadStream: (opts) => fs.createReadStream(localFilePath, opts)
      };
      mockVideoFile.torrent = { path: cachePath, name: dn };

      const torrentData = {
        torrent: mockVideoFile.torrent,
        videoFile: mockVideoFile
      };
      activeTorrents.set(magnetURI, torrentData);
      return Promise.resolve(torrentData);
    }
  }

  const torrentPromise = new Promise((resolve, reject) => {
    
    console.log('Adding Torrent...');
    let torrent;
    
    try {
      torrent = client.add(magnetURI, {
        path: process.env.CACHE_PATH,
        deselect: true
      });
    } catch (err) {
      if (err.message.includes('duplicate')) {
        console.log('Torrent already exists in client. Retrieving...');
        torrent = client.get(magnetURI);
      } else {
        activeTorrents.delete(magnetURI);
        return reject(err);
      }
    }

    // Failsafe in case the retrieved object is invalid or destroyed
    if (!torrent || typeof torrent.on !== 'function') {
      console.error('Invalid torrent object retrieved from WebTorrent');
      activeTorrents.delete(magnetURI);
      return reject(new Error('Invalid torrent object'));
    }

    const handleReady = () => {
      console.log('Torrent Ready');
      console.log('Files Found:');

      torrent.files.forEach(file => {
        console.log(file.name);
      });

      const supportedExtensions = [
        '.mp4',
        '.mkv',
        '.avi',
        '.mov',
        '.webm',
        '.m4v'
      ];

      let videoFile;

      if (fileIdx !== undefined) {
        console.log(`Using provided fileIdx: ${fileIdx}`);
        videoFile = torrent.files[fileIdx];
      } else {
        const videoFiles = torrent.files.filter(file => {
          const name = file.name.toLowerCase();
          const isVideo = supportedExtensions.some(ext => name.endsWith(ext));
          // Filter out small files likely to be samples (< 50MB)
          const isLargeEnough = file.length > 50 * 1024 * 1024;
          return isVideo && isLargeEnough;
        });

        console.log('Detected Video Files:');
        videoFiles.forEach(file => {
          console.log(file.name, Math.round(file.length / (1024 * 1024)), 'MB');
        });

        videoFile = videoFiles.sort((a, b) => b.length - a.length)[0];
      }

      if (!videoFile) {
        console.log('No Suitable Video File Found');
        torrent.files.forEach(file => {
          console.log(file.name);
        });
        activeTorrents.delete(magnetURI);
        try { torrent.destroy(); } catch (e) {}
        return reject(new Error('No suitable video file found'));
      }

      console.log('Selected Video File:');
      console.log(videoFile.name);

      // FORCE Webtorrent to stop downloading all other files
      torrent.deselect(0, torrent.pieces.length - 1, false);
      torrent.files.forEach(f => f.deselect());

      // Select only our target file
      if (streaming) {
        // Sequential download for streaming
        // In streaming mode, StreamManager handles dynamic prioritization
        // We just do a basic select here
        videoFile.select();
      } else {
        videoFile.select();
      }

      const torrentData = {
        torrent,
        videoFile
      };

      resolve(torrentData);
    };

    let metadataTimeout;

    if (torrent.ready) {
      handleReady();
    } else {
      torrent.on('ready', () => {
        clearTimeout(metadataTimeout);
        handleReady();
      });
      
      // Set a 55-second timeout for fetching metadata
      metadataTimeout = setTimeout(() => {
        console.error('Timeout fetching torrent metadata');
        activeTorrents.delete(magnetURI);
        try { torrent.destroy(); } catch (e) {}
        reject(new Error('Timeout fetching torrent metadata. The torrent might have no seeders or the network is slow.'));
      }, 55000);
    }

    torrent.on('download', bytes => {
      const percent = (torrent.progress * 100).toFixed(2);
      const speed = (torrent.downloadSpeed / 1024 / 1024).toFixed(2);
      process.stdout.write(`\rDownloading: ${percent}% | ${speed} MB/s`);
    });

    torrent.on('done', () => {
      console.log('\nTorrent Download Complete');
    });

    torrent.on('error', err => {
      console.error('WebTorrent Error:', err);
      activeTorrents.delete(magnetURI);
      try { torrent.destroy(); } catch(e){}
      reject(err);
    });

  });

  // Store the Promise IMMEDIATELY so concurrent requests wait for the same setup
  activeTorrents.set(magnetURI, torrentPromise);

  // Once resolved, replace the Promise in the map with the actual torrentData object
  torrentPromise.then(data => {
    activeTorrents.set(magnetURI, data);
  }).catch(() => {
    activeTorrents.delete(magnetURI);
  });

  return torrentPromise;
}

export function destroyTorrent(magnetURI) {
  const data = activeTorrents.get(magnetURI);
  if (!data) return;
  
  try {
    if (data.torrent && !data.videoFile?.isLocal) {
      data.torrent.destroy();
    }
  } catch (e) {}
  
  activeTorrents.delete(magnetURI);
}

export function getTorrentPieceInfo(torrentData) {
  if (!torrentData || !torrentData.torrent || torrentData.videoFile?.isLocal) {
    return null;
  }
  
  const torrent = torrentData.torrent;
  const videoFile = torrentData.videoFile;
  
  return {
    pieceLength: torrent.pieceLength,
    totalPieces: torrent.pieces.length,
    fileOffset: videoFile.offset,
    fileLength: videoFile.length,
    startPiece: Math.floor(videoFile.offset / torrent.pieceLength),
    endPiece: Math.floor((videoFile.offset + videoFile.length) / torrent.pieceLength)
  };
}

export {
  activeTorrents,
  client
};