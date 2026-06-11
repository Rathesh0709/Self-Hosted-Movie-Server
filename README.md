# Self-Hosted Movie Server

A self-hosted movie streaming stack: a **Node.js backend** that sources movies via
torrents and streams them on demand, paired with a **Flutter client app ("Streamflix")**
for browsing and playback.

## Components

### `Stream-server-backend/` — Node.js (Express) API + streaming server
- **Torrent-based sourcing:** `webtorrent` to fetch/seed movie content.
- **On-the-fly transcoding & streaming:** `fluent-ffmpeg` for transcoding, HTTP range
  streaming to the client.
- **Realtime updates:** `socket.io` (e.g. download/stream progress).
- **Scraping:** `playwright` for sourcing metadata/links.
- **Auth & storage:** `jsonwebtoken` + `bcryptjs` for auth, `better-sqlite3` for local
  data persistence.
- Entry point: `src/server.js` (`npm start` / `npm run dev` with nodemon).

### `Streamflix/` — Flutter client app
- Cross-platform UI (Android / web / Windows) for browsing the catalog and streaming
  movies from the backend.

## Tech stack

- **Backend:** Node.js (ESM), Express 5, WebTorrent, fluent-ffmpeg, Socket.IO,
  Playwright, better-sqlite3, JWT
- **Frontend:** Flutter / Dart
- **Requires:** [FFmpeg](https://ffmpeg.org/) installed on the host

## Getting started

### Backend
```bash
cd Stream-server-backend
npm install
# create a .env with your config (JWT secret, ports, paths)
npm start          # or: npm run dev
```

### Flutter app
```bash
cd Streamflix
flutter pub get
flutter run
```
Point the app at your backend's address (e.g. over LAN / Tailscale).

> ⚠️ Stream only content you are legally permitted to access. This project is for
> personal, self-hosted use.
