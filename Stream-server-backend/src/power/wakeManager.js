class WakeManager {
  getServerUptime() {
    return process.uptime();
  }

  isOnline() {
    return true; // If this code runs, the server is online
  }
}

export const wakeManager = new WakeManager();
