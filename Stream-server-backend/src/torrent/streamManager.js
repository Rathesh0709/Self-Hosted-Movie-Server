import fs from 'fs';
import path from 'path';
import { activeTorrents } from './torrentManager.js';

class StreamManager {
  constructor() {
    // streamId → { torrentData, activeRequests, priorityState, lastActivity, fileRangeStreamPool }
    this.sessions = new Map();
    
    // Configuration
    this.BUFFER_AHEAD_SECONDS = 180;     // 3 minutes read-ahead
    this.SEEK_PRIORITY_SECONDS = 300;    // 5 minutes aggressive after seek
    this.CRITICAL_BUFFER_SECONDS = 30;   // First 30s are critical priority
    this.CLEANUP_INTERVAL_MS = 15 * 60 * 1000; // 15 mins
    
    setInterval(() => this.cleanupIdleSessions(), this.CLEANUP_INTERVAL_MS);
  }

  /**
   * Register a new stream session
   */
  registerStream(streamId, torrentData) {
    if (!this.sessions.has(streamId)) {
      this.sessions.set(streamId, {
        torrentData,
        activeRequests: 0,
        lastActivity: Date.now(),
        playbackByteOffset: 0,
        priorityState: {
          currentPiece: -1,
          isSeeking: false
        }
      });
      console.log(`[STREAM_MANAGER] Registered stream ${streamId}`);
    }
  }

  /**
   * Get an active stream session
   */
  getSession(streamId) {
    return this.sessions.get(streamId);
  }

  /**
   * Create a range stream for the client (avoids WebTorrent stream recreation bugs)
   * We still use WebTorrent's createReadStream but we manage the lifecycle properly
   * and integrate it with our piece prioritization.
   */
  createRangeStream(streamId, start, end) {
    const session = this.sessions.get(streamId);
    if (!session) throw new Error('Stream session not found');

    session.lastActivity = Date.now();
    session.activeRequests++;

    const { videoFile } = session.torrentData;
    
    console.log(`[STREAM_MANAGER] Creating range stream for ${streamId}: ${start}-${end}`);
    
    // Trigger prioritization for this new range
    this.prioritizePieces(streamId, start);

    const stream = videoFile.createReadStream({ start, end });
    
    // We attach a custom cleanup method to the stream to decrement activeRequests
    // but we don't immediately destroy the underlying WebTorrent stream if there are
    // other active requests.
    const originalDestroy = stream.destroy.bind(stream);
    
    let isDestroyed = false;
    stream.cleanup = () => {
      if (isDestroyed) return;
      isDestroyed = true;
      session.activeRequests--;
      console.log(`[STREAM_MANAGER] Stream ${streamId} request ended. Active requests: ${session.activeRequests}`);
      try { originalDestroy(); } catch (e) {}
    };

    stream.on('close', stream.cleanup);
    stream.on('error', stream.cleanup);

    return stream;
  }

  /**
   * Called by the client periodically to update current playback position
   */
  reportPlaybackPosition(streamId, byteOffset) {
    const session = this.sessions.get(streamId);
    if (!session) return;

    session.lastActivity = Date.now();
    
    // Only reprioritize if we've moved significantly (e.g., crossed a piece boundary)
    // We'll let prioritizePieces handle the piece math
    this.prioritizePieces(streamId, byteOffset);
  }

  /**
   * Handle user seek
   */
  handleSeek(streamId, newByteOffset) {
    const session = this.sessions.get(streamId);
    if (!session) return;

    session.lastActivity = Date.now();
    session.priorityState.isSeeking = true;
    
    console.log(`[STREAM_MANAGER] Handling seek for ${streamId} to offset ${newByteOffset}`);
    
    this.prioritizePieces(streamId, newByteOffset, true);
    
    // Reset seeking flag after a short delay
    setTimeout(() => {
      if (this.sessions.has(streamId)) {
        this.sessions.get(streamId).priorityState.isSeeking = false;
      }
    }, 2000);
  }

  /**
   * Core logic to tell WebTorrent which pieces to download first
   */
  prioritizePieces(streamId, byteOffset, isSeek = false) {
    const session = this.sessions.get(streamId);
    if (!session || !session.torrentData || !session.torrentData.torrent) return;

    const { torrent, videoFile } = session.torrentData;
    if (torrent.done || videoFile.isLocal) return; // Nothing to prioritize if finished or local

    const pieceLength = torrent.pieceLength;
    if (!pieceLength) return;

    // Clamp everything to THIS file's piece range so we never start pulling the
    // neighbouring episodes in a season-pack torrent (which was filling the
    // cache with files the user never selected).
    const fileStartPiece = Math.floor(videoFile.offset / pieceLength);
    const fileEndPiece = Math.floor((videoFile.offset + videoFile.length - 1) / pieceLength);

    // Calculate piece index for the requested byte offset within the video file
    const absoluteOffset = videoFile.offset + byteOffset;
    const currentPiece = Math.max(fileStartPiece, Math.floor(absoluteOffset / pieceLength));

    // Only update if the piece changed or we are seeking
    if (currentPiece === session.priorityState.currentPiece && !isSeek) {
      return;
    }

    session.priorityState.currentPiece = currentPiece;
    session.playbackByteOffset = byteOffset;

    const bytesPerSecond = torrent.downloadSpeed || 1000000; // default 1MB/s estimate

    // Calculate how many pieces ahead we want based on config and speed
    const bufferSeconds = isSeek ? this.SEEK_PRIORITY_SECONDS : this.BUFFER_AHEAD_SECONDS;
    const criticalSeconds = this.CRITICAL_BUFFER_SECONDS;

    const bufferBytes = bufferSeconds * bytesPerSecond;
    const criticalBytes = criticalSeconds * bytesPerSecond;

    const bufferEndPiece = Math.min(
      Math.floor((absoluteOffset + bufferBytes) / pieceLength),
      fileEndPiece
    );

    const criticalEndPiece = Math.min(
      Math.floor((absoluteOffset + criticalBytes) / pieceLength),
      fileEndPiece
    );

    // Deprioritize everything if seeking to clear the download queue
    if (isSeek) {
      torrent.deselect(0, torrent.pieces.length - 1, false);
    }

    // 1. Prioritize buffer window (priority 1)
    if (currentPiece <= bufferEndPiece) {
      torrent.select(currentPiece, bufferEndPiece, 1);
    }

    // 2. Set critical pieces for immediate playback
    if (currentPiece <= criticalEndPiece) {
      torrent.critical(currentPiece, criticalEndPiece);
    }

    // Log if it's a significant change
    if (isSeek || currentPiece % 5 === 0) {
      console.log(`[STREAM_MANAGER] ${streamId} priority: critical ${currentPiece}-${criticalEndPiece}, buffer ${currentPiece}-${bufferEndPiece}`);
    }
  }

  /**
   * Get health and buffer status of a stream
   */
  getStreamHealth(streamId) {
    const session = this.sessions.get(streamId);
    if (!session || !session.torrentData) return null;

    const { torrent, videoFile } = session.torrentData;
    
    if (videoFile.isLocal || torrent.done) {
      return {
        bufferAheadSeconds: 9999,
        downloadSpeed: 0,
        torrentProgress: 100,
        health: 'excellent'
      };
    }

    const downloadSpeed = torrent.downloadSpeed || 0;
    const torrentProgress = (torrent.progress * 100) || 0;
    
    // Estimate buffer ahead based on downloaded pieces starting from current position
    let bufferAheadBytes = 0;
    let health = 'poor';

    if (session.priorityState.currentPiece >= 0) {
      const startPiece = session.priorityState.currentPiece;
      let consecutivePieces = 0;
      
      for (let i = startPiece; i < torrent.pieces.length; i++) {
        // web-torrent piece array check (it might be torrent.bitfield.get(i) in some versions, or torrent.pieces[i])
        // Webtorrent exposes torrent.pieces (array of Piece objects) or torrent.bitfield
        let hasPiece = false;
        if (torrent.bitfield) {
          hasPiece = torrent.bitfield.get(i);
        } else if (torrent.pieces && torrent.pieces[i]) {
           hasPiece = torrent.pieces[i].length === torrent.pieceLength; // Rough check
        }

        if (hasPiece) {
          consecutivePieces++;
        } else {
          break; // Stop at first missing piece
        }
      }
      
      bufferAheadBytes = consecutivePieces * torrent.pieceLength;
    }

    // Rough conversion to seconds (assumes 5MB/minute average bitrate = ~80KB/s)
    const assumedBitrate = 80000; 
    const bufferAheadSeconds = Math.round(bufferAheadBytes / assumedBitrate);

    if (bufferAheadSeconds > 120) health = 'excellent';
    else if (bufferAheadSeconds > 30) health = 'good';
    else if (bufferAheadSeconds > 10) health = 'fair';

    return {
      bufferAheadSeconds,
      downloadSpeed,
      torrentProgress: Number(torrentProgress.toFixed(2)),
      health
    };
  }

  /**
   * Get global status across all streams
   */
  getGlobalStatus() {
    let totalSpeed = 0;
    let minHealth = 'excellent';
    const activeStreams = this.sessions.size;

    for (const streamId of this.sessions.keys()) {
      const health = this.getStreamHealth(streamId);
      if (health) {
        totalSpeed += health.downloadSpeed;
        if (health.health === 'poor') minHealth = 'poor';
        else if (health.health === 'fair' && minHealth !== 'poor') minHealth = 'fair';
        else if (health.health === 'good' && (minHealth === 'excellent')) minHealth = 'good';
      }
    }

    return {
      activeStreams,
      downloadSpeed: totalSpeed,
      health: minHealth
    };
  }

  /**
   * Remove a stream session
   */
  cleanupStream(streamId) {
    if (this.sessions.has(streamId)) {
      this.sessions.delete(streamId);
      console.log(`[STREAM_MANAGER] Cleaned up stream ${streamId}`);
    }
  }

  /**
   * Clean up sessions inactive for > 4 hours
   */
  cleanupIdleSessions() {
    const now = Date.now();
    const TIMEOUT = 4 * 60 * 60 * 1000; // 4 hours

    for (const [streamId, session] of this.sessions.entries()) {
      if (now - session.lastActivity > TIMEOUT) {
        console.log(`[STREAM_MANAGER] Removing idle stream ${streamId}`);
        this.cleanupStream(streamId);
      }
    }
  }
}

export const streamManager = new StreamManager();
