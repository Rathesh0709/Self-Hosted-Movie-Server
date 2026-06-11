import path from 'path';
import fs from 'fs';
import { activeTorrents, startTorrent, destroyTorrent } from './torrentManager.js';

class DownloadManager {
  constructor() {
    this.activeDownloads = new Map(); // magnetURI -> { torrent, startedAt }
    
    // Periodically check for completed downloads and clean up
    setInterval(() => this.checkCompletedDownloads(), 30000);
  }

  async addDownload(magnetURI, fileIdx) {
    if (this.activeDownloads.has(magnetURI)) {
      return { success: true, message: 'Already downloading' };
    }

    try {
      // Not streaming, we want to download all pieces
      const torrentData = await startTorrent(magnetURI, fileIdx, false);
      
      this.activeDownloads.set(magnetURI, {
        torrent: torrentData.torrent,
        videoFile: torrentData.videoFile,
        startedAt: Date.now()
      });
      
      console.log(`[DOWNLOAD_MANAGER] Added download for ${magnetURI}`);
      
      return {
        success: true,
        message: 'Download added',
        file: {
          name: torrentData.videoFile.name,
          size: torrentData.videoFile.length
        }
      };
    } catch (err) {
      console.error(`[DOWNLOAD_MANAGER] Failed to add download: ${err.message}`);
      throw err;
    }
  }

  removeDownload(magnetURI) {
    if (this.activeDownloads.has(magnetURI)) {
      const { torrent } = this.activeDownloads.get(magnetURI);
      if (torrent && !torrent.done) {
        destroyTorrent(magnetURI);
      }
      this.activeDownloads.delete(magnetURI);
      console.log(`[DOWNLOAD_MANAGER] Removed download for ${magnetURI}`);
    }
  }

  getActiveDownloads() {
    const items = [];
    for (const [magnetURI, data] of this.activeDownloads.entries()) {
      const torrent = data.torrent;
      items.push({
        magnetURI,
        name: data.videoFile?.name,
        progress: Number(((torrent?.progress ?? 1) * 100).toFixed(2)),
        downloadSpeed: torrent?.downloadSpeed ?? 0,
        numPeers: torrent?.numPeers ?? 0,
        done: !!torrent?.done,
      });
    }
    return items;
  }

  isDownloading(magnetURI) {
    return this.activeDownloads.has(magnetURI);
  }
  
  checkCompletedDownloads() {
    for (const [magnetURI, data] of this.activeDownloads.entries()) {
      if (data.torrent && data.torrent.done) {
        console.log(`[DOWNLOAD_MANAGER] Download complete for ${data.videoFile?.name}`);
        // We can keep it seeding, or remove it from active downloads tracking
        this.activeDownloads.delete(magnetURI);
      }
    }
  }
}

export const downloadManager = new DownloadManager();
