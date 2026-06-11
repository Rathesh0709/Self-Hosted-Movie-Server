import fs from 'fs';
import path from 'path';

const CACHE_PATH = process.env.CACHE_PATH || path.resolve(process.cwd(), 'cache');

function getFolderSizeAndFiles(folderPath, filesList = []) {
  let totalSize = 0;
  if (!fs.existsSync(folderPath)) return { totalSize, filesList };
  
  const items = fs.readdirSync(folderPath);

  for (const item of items) {
    const itemPath = path.join(folderPath, item);
    const stats = fs.statSync(itemPath);

    if (stats.isDirectory()) {
      const res = getFolderSizeAndFiles(itemPath, filesList);
      totalSize += res.totalSize;
    } else {
      totalSize += stats.size;
      filesList.push({
        path: itemPath,
        size: stats.size,
        atimeMs: stats.atimeMs,
        mtimeMs: stats.mtimeMs
      });
    }
  }

  return { totalSize, filesList };
}

export function cleanupOldCache(maxSizeGB = process.env.MAX_CACHE_GB || 50) {
  const maxBytes = maxSizeGB * 1024 * 1024 * 1024;
  const { totalSize, filesList } = getFolderSizeAndFiles(CACHE_PATH);

  console.log(`[CACHE_MANAGER] Current Cache Size: ${(totalSize / 1024 / 1024 / 1024).toFixed(2)} GB`);

  if (totalSize < maxBytes) {
    return;
  }

  console.log(`[CACHE_MANAGER] Cache cleanup needed. Max allowed: ${maxSizeGB} GB`);
  
  // Sort files by access time (oldest first)
  filesList.sort((a, b) => a.atimeMs - b.atimeMs);
  
  let currentSize = totalSize;
  let deletedCount = 0;
  
  for (const file of filesList) {
    if (currentSize <= maxBytes) break;
    
    try {
      fs.unlinkSync(file.path);
      currentSize -= file.size;
      deletedCount++;
      console.log(`[CACHE_MANAGER] Deleted old cache file: ${file.path}`);
    } catch (err) {
      console.error(`[CACHE_MANAGER] Failed to delete file ${file.path}:`, err.message);
    }
  }
  
  console.log(`[CACHE_MANAGER] Cleanup complete. Deleted ${deletedCount} files.`);
}

// Schedule periodic cleanup (every hour)
setInterval(() => cleanupOldCache(), 60 * 60 * 1000);