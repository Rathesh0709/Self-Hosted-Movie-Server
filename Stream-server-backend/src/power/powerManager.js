import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';
import axios from 'axios';
import { activeTorrents } from '../torrent/torrentManager.js';
import dotenv from 'dotenv';
dotenv.config();

class PowerManager {
  constructor() {
    this.activeStreams = new Set();
    this.activeDownloads = new Set();
    this.lastActivityTimestamp = Date.now();
    
    this.IDLE_TIMEOUT_MINUTES = Number(process.env.IDLE_TIMEOUT_MINUTES) || 30;
    this.CHECK_INTERVAL_MS = 60000; // Check every minute

    // Minimum time the server must stay awake after boot/wake before it can sleep again.
    // This prevents the sleep→wake→sleep restart loop.
    this.MIN_AWAKE_DURATION_MS = 30 * 60 * 1000; // 30 minutes
    this.wakeTimestamp = Date.now(); // Tracks when the server last booted or was woken

    // Peer (music) backend power endpoint. The PC is shared, so only sleep when
    // the music backend is idle too.
    this.PEER_POWER_URL =
      process.env.PEER_POWER_URL || 'http://localhost:4000/api/power';
    
    const dataDir = path.resolve(process.cwd(), 'data');
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }
    this.STATE_FILE = path.join(dataDir, 'power-state.json');
    
    // Delay starting the idle checker until after MIN_AWAKE_DURATION_MS to avoid
    // the restart loop. The interval still ticks every minute, but checkIdle()
    // has its own guard, so starting immediately is fine — the guard will reject.
    this.sleepInterval = setInterval(() => this.checkIdle(), this.CHECK_INTERVAL_MS);
    this.sleepScheduled = false;
    this.sleepInMinutes = null;

    console.log(`[POWER_MANAGER] Initialized. Min awake duration: ${this.MIN_AWAKE_DURATION_MS / 60000} min, idle timeout: ${this.IDLE_TIMEOUT_MINUTES} min`);
  }

  /**
   * Called when the server is woken up (via WoL or manual wake endpoint).
   * Resets the wake timestamp so the 30-min guard starts fresh.
   */
  recordWake() {
    this.wakeTimestamp = Date.now();
    this.lastActivityTimestamp = Date.now();
    this.cancelScheduledSleep();
    console.log('[POWER_MANAGER] Wake recorded. Sleep guard active for 30 minutes.');
  }

  registerStreamActivity(streamId) {
    this.activeStreams.add(streamId);
    this.recordUserActivity();
  }

  unregisterStreamActivity(streamId) {
    this.activeStreams.delete(streamId);
    this.recordUserActivity();
  }

  registerDownloadActivity(magnetURI) {
    this.activeDownloads.add(magnetURI);
    this.recordUserActivity();
  }

  unregisterDownloadActivity(magnetURI) {
    this.activeDownloads.delete(magnetURI);
    this.recordUserActivity();
  }

  recordUserActivity() {
    this.lastActivityTimestamp = Date.now();
    if (this.sleepScheduled) {
      this.cancelScheduledSleep();
    }
  }

  getStatus() {
    const now = Date.now();
    const awakeDurationMs = now - this.wakeTimestamp;
    const minAwakeRemainingMs = Math.max(0, this.MIN_AWAKE_DURATION_MS - awakeDurationMs);

    return {
      activeStreams: this.activeStreams.size,
      activeDownloads: this.activeDownloads.size,
      idleMinutes: Math.floor((now - this.lastActivityTimestamp) / 60000),
      sleepScheduled: this.sleepScheduled,
      sleepInMinutes: this.sleepInMinutes,
      wakeTimestamp: this.wakeTimestamp,
      minAwakeRemainingMinutes: Math.ceil(minAwakeRemainingMs / 60000),
    };
  }

  /**
   * Returns true if the peer (music) backend is busy — active streams/downloads
   * or not yet idle. Unreachable peer → treated as not busy.
   */
  async peerBusy() {
    if (!this.PEER_POWER_URL) return false;
    try {
      const { data } = await axios.get(`${this.PEER_POWER_URL}/status`, { timeout: 4000 });
      const active = (data.activeStreams || 0) > 0 || (data.activeDownloads || 0) > 0;
      const peerIdle = (data.idleMinutes ?? 0) >= this.IDLE_TIMEOUT_MINUTES;
      return active || !peerIdle;
    } catch {
      return false; // peer unreachable → not busy
    }
  }

  async checkIdle() {
    // Guard 1: Don't sleep if there are active streams or downloads
    if (this.activeStreams.size > 0 || this.activeDownloads.size > 0) {
      return;
    }

    // Guard 2: Don't sleep within MIN_AWAKE_DURATION_MS of boot/wake
    const awakeDuration = Date.now() - this.wakeTimestamp;
    if (awakeDuration < this.MIN_AWAKE_DURATION_MS) {
      return;
    }

    const idleMinutes = Math.floor((Date.now() - this.lastActivityTimestamp) / 60000);

    if (idleMinutes >= this.IDLE_TIMEOUT_MINUTES && !this.sleepScheduled) {
      // Guard 3: the music backend must also be idle (shared PC).
      if (await this.peerBusy()) {
        console.log('[POWER_MANAGER] Idle, but peer (music) backend is busy — staying awake.');
        return;
      }
      this.executeSleep();
    }
  }

  scheduleSleep() {
    this.sleepScheduled = true;
    this.sleepInMinutes = 5; // give a 5-minute grace period (optional)
  }

  cancelScheduledSleep() {
    this.sleepScheduled = false;
    this.sleepInMinutes = null;
  }

  async executeSleep() {
    console.log('[POWER_MANAGER] Executing sleep...');
    
    // 1. Save state
    await this.saveState();
    
    // 2. Execute sleep command (Windows specific)
    // Warning: requires privileges
    exec('rundll32.exe powrprof.dll,SetSuspendState 0,1,0', (err) => {
      if (err) {
        console.error('[POWER_MANAGER] Failed to sleep:', err);
      }
    });
  }

  async saveState() {
    const state = {
      activeTorrents: [...activeTorrents.entries()].map(([uri, data]) => ({
        magnetURI: uri,
        fileName: data.videoFile?.name,
        progress: data.torrent?.progress,
      })),
      timestamp: Date.now(),
    };
    fs.writeFileSync(this.STATE_FILE, JSON.stringify(state, null, 2));
    console.log('[POWER_MANAGER] State saved for wake recovery');
  }
}

export const powerManager = new PowerManager();
