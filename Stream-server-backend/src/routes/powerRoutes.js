import express from 'express';
import { powerManager } from '../power/powerManager.js';
import { wakeManager } from '../power/wakeManager.js';

const router = express.Router();

router.get('/status', (req, res) => {
  const status = powerManager.getStatus();
  res.json({
    online: wakeManager.isOnline(),
    uptime: wakeManager.getServerUptime(),
    activeStreams: status.activeStreams,
    activeDownloads: status.activeDownloads,
    idleMinutes: status.idleMinutes,
    sleepScheduled: status.sleepScheduled,
    sleepIn: status.sleepInMinutes, // null if not scheduled
    wakeTimestamp: status.wakeTimestamp,
    minAwakeRemainingMinutes: status.minAwakeRemainingMinutes,
  });
});

router.post('/sleep', async (req, res) => {
  try {
    await powerManager.executeSleep();
    res.json({ success: true, message: 'Sleep initiated' });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to initiate sleep' });
  }
});

router.post('/wake', (req, res) => {
  powerManager.recordWake();
  res.json({ success: true, message: 'Wake recorded, sleep guard active for 30 minutes' });
});

export default router;
