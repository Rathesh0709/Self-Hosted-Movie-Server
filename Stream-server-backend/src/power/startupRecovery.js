import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';
import util from 'util';
import axios from 'axios';
import { startTorrent } from '../torrent/torrentManager.js';
import dotenv from 'dotenv';
dotenv.config();

const execAsync = util.promisify(exec);

export class StartupRecovery {
  constructor() {
    const dataDir = path.resolve(process.cwd(), 'data');
    this.STATE_FILE = path.join(dataDir, 'power-state.json');
  }
  
  async recover() {
    if (!fs.existsSync(this.STATE_FILE)) return;
    
    let state;
    try {
      const raw = fs.readFileSync(this.STATE_FILE, 'utf-8');
      state = JSON.parse(raw);
    } catch (parseErr) {
      console.error(`[RECOVERY] Corrupt or unreadable state file, deleting: ${parseErr.message}`);
      try { fs.unlinkSync(this.STATE_FILE); } catch {}
      return;
    }

    // Delete state file FIRST to prevent re-triggering sleep on crash during recovery.
    // This breaks the sleep→wake→crash→sleep loop.
    try {
      fs.unlinkSync(this.STATE_FILE);
      console.log('[RECOVERY] State file deleted (pre-recovery cleanup)');
    } catch (unlinkErr) {
      console.warn('[RECOVERY] Could not delete state file:', unlinkErr.message);
    }

    try {
      console.log(`[RECOVERY] Restoring from saved state (${new Date(state.timestamp).toISOString()})`);
      
      // 1. Restore active torrents
      if (state.activeTorrents && Array.isArray(state.activeTorrents)) {
        for (const torrent of state.activeTorrents) {
          try {
            console.log(`[RECOVERY] Re-adding torrent: ${torrent.fileName}`);
            await startTorrent(torrent.magnetURI, undefined, false); // Resume download/streaming
          } catch (err) {
            console.error(`[RECOVERY] Failed to restore torrent: ${err.message}`);
          }
        }
      }
      
      // 2. Verify Tailscale connectivity
      await this.checkTailscale();
      
      // 3. Verify Prowlarr connectivity  
      await this.checkProwlarr();
      
      console.log('[RECOVERY] Startup recovery complete');
    } catch (e) {
      console.error(`[RECOVERY] Error during recovery: ${e.message}`);
    }
  }
  
  async checkTailscale() {
    try {
      const { stdout } = await execAsync('tailscale status --json');
      const status = JSON.parse(stdout);
      if (status.BackendState !== 'Running') {
        console.warn('[RECOVERY] Tailscale not running, attempting reconnect...');
        await execAsync('tailscale up');
      } else {
        console.log('[RECOVERY] Tailscale is running');
      }
    } catch (err) {
      console.warn('[RECOVERY] Tailscale check failed (ensure tailscale CLI is available):', err.message);
    }
  }
  
  async checkProwlarr() {
    try {
      const prowlarrUrl = process.env.PROWLARR_URL || 'http://localhost:9696';
      await axios.get(`${prowlarrUrl}/api/v1/health`, { timeout: 5000 });
      console.log('[RECOVERY] Prowlarr is online');
    } catch {
      console.warn('[RECOVERY] Prowlarr is offline — it may need manual restart');
    }
  }
}
