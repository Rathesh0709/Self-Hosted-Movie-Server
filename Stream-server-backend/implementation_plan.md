# StreamFlix Feature Expansion — Auth, Favorites, Media Library, Categories

This plan adds authentication, user favorites, a downloaded media library, anime/cartoon categories, and an expanded navigation system to the existing StreamFlix torrent streaming app.

## User Review Required

> [!IMPORTANT]
> **Database Choice**: This plan uses **SQLite** (via `better-sqlite3`) for user accounts and favorites. It's self-contained (no external DB server needed), perfect for a self-hosted media server. If you prefer MongoDB or PostgreSQL, let me know.

> [!IMPORTANT]
> **Anime vs Cartoon Detection**: TMDB doesn't have a separate "anime" media type. The plan uses **genre-based filtering**:
> - **Anime**: TV shows/movies with Animation genre (16) AND origin country = Japan (`origin_country: ["JP"]`), or with anime-related keywords
> - **Cartoons**: TV shows/movies with Animation genre (16) that are NOT anime (Western animation)
> 
> This approach works well for most content but won't be 100% perfect for edge cases.

> [!WARNING]
> **Auth tokens are stored in localStorage**. This is standard for SPAs but means anyone with physical access to the browser can see the token. Since this is a personal/self-hosted server, this should be acceptable.

## Open Questions

> [!IMPORTANT]
> **Navigation Structure**: You mentioned wanting tabs for: Home, Search, Downloaded, Favourites, Popular RN, Movies, TV Shows, Animes. That's 8 items which is a lot for mobile bottom nav. The plan implements:
> - **Mobile bottom nav**: Home, Search, Library (contains Downloads + Favourites), Profile (auth)
> - **Desktop top nav**: All categories as separate links
> - **Home page**: Popular RN, Movies, TV Shows, Anime, Cartoons sections as carousels
> 
> Does this approach work, or do you want all 8 items visible on mobile too?

## Proposed Changes

### Component 1: Backend — Database & Auth System

New SQLite database for users and favorites. JWT-based auth with email/password.

---

#### [NEW] [database.js](file:///d:/Stream-server-backend/src/database/database.js)
- Initialize SQLite database with `better-sqlite3`
- Create `users` table: `id`, `email`, `password_hash`, `created_at`
- Create `favorites` table: `id`, `user_id`, `media_id`, `media_type`, `title`, `poster_path`, `backdrop_path`, `vote_average`, `added_at`
- Auto-create tables on startup

#### [NEW] [authMiddleware.js](file:///d:/Stream-server-backend/src/middleware/authMiddleware.js)
- JWT verification middleware
- Extracts user from `Authorization: Bearer <token>` header
- Sets `req.user` with `{ id, email }`
- Optional auth middleware variant for routes that work with or without auth

#### [NEW] [authRoutes.js](file:///d:/Stream-server-backend/src/routes/authRoutes.js)
- `POST /api/auth/register` — Create account (email + password), returns JWT
- `POST /api/auth/login` — Login with email + password, returns JWT
- `GET /api/auth/me` — Get current user profile (protected)
- `PUT /api/auth/change-password` — Change password (protected)
- Password hashing via `bcryptjs`
- JWT signing via `jsonwebtoken`

---

### Component 2: Backend — Favorites API

Per-user favorites CRUD endpoints, all protected by auth middleware.

---

#### [NEW] [favoritesRoutes.js](file:///d:/Stream-server-backend/src/routes/favoritesRoutes.js)
- `GET /api/favorites` — List all user's favorites (protected)
- `POST /api/favorites` — Add a favorite (media_id, media_type, title, poster, etc.)
- `DELETE /api/favorites/:mediaId/:mediaType` — Remove a favorite
- `GET /api/favorites/check/:mediaId/:mediaType` — Check if item is favorited

#### [MODIFY] [server.js](file:///d:/Stream-server-backend/src/server.js)
- Import and mount `authRoutes` at `/api/auth`
- Import and mount `favoritesRoutes` at `/api/favorites`  
- Import and initialize database on startup

#### [MODIFY] [package.json](file:///d:/Stream-server-backend/package.json)
- Add dependencies: `better-sqlite3`, `bcryptjs`, `jsonwebtoken`

#### [MODIFY] [.env](file:///d:/Stream-server-backend/.env)
- Add `JWT_SECRET` environment variable

---

### Component 3: Frontend — Auth System

Login/Register pages, auth store, and protected route handling.

---

#### [NEW] [authStore.ts](file:///d:/Stream-Server-Frontend/src/store/authStore.ts)
- Zustand store with `persist` middleware
- State: `user`, `token`, `isAuthenticated`
- Actions: `login()`, `register()`, `logout()`, `loadUser()`
- Stores JWT in localStorage via Zustand persist

#### [NEW] [authService.ts](file:///d:/Stream-Server-Frontend/src/services/authService.ts)
- `register(email, password)` — POST to `/api/auth/register`
- `login(email, password)` — POST to `/api/auth/login`
- `getProfile()` — GET `/api/auth/me`
- `changePassword(currentPassword, newPassword)`
- All requests include `Authorization` header from auth store

#### [NEW] [AuthPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/AuthPage.tsx)
- Combined Login/Register page with tab toggle
- Email + password form fields
- Form validation, error display
- Redirects to `/home` on success
- Premium glassmorphic design matching app aesthetic

#### [MODIFY] [api.ts](file:///d:/Stream-Server-Frontend/src/services/api.ts)
- Add auth token interceptor to `backendClient` — automatically attaches JWT to all backend requests

#### [MODIFY] [App.tsx](file:///d:/Stream-Server-Frontend/src/App.tsx)
- Add `/auth` route for AuthPage
- Add `/library` route for LibraryPage
- Add `/favorites` route for FavoritesPage  
- Add category routes: `/movies`, `/tvshows`, `/anime`, `/cartoons`
- Add route for `/popular`

---

### Component 4: Frontend — Favorites System

Favorite toggle button on media details, favorites page with grid view.

---

#### [NEW] [favoritesService.ts](file:///d:/Stream-Server-Frontend/src/services/favoritesService.ts)
- `getFavorites()` — Fetch user's favorites list
- `addFavorite(mediaItem)` — Add to favorites
- `removeFavorite(mediaId, mediaType)` — Remove from favorites
- `checkFavorite(mediaId, mediaType)` — Check if favorited

#### [NEW] [favoritesStore.ts](file:///d:/Stream-Server-Frontend/src/store/favoritesStore.ts)
- Zustand store for local favorites cache
- Syncs with backend on login
- Optimistic updates for instant UI feedback

#### [NEW] [FavoritesPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/FavoritesPage.tsx)
- Grid display of all favorited movies and TV shows
- Filter tabs: All, Movies, TV Shows, Anime
- Empty state with call-to-action
- Remove favorite with swipe/button

#### [MODIFY] [DetailsPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/DetailsPage.tsx)
- Add heart/favorite toggle button in the details header
- Shows filled heart if favorited, outline if not
- Requires authentication — shows login prompt if not logged in

---

### Component 5: Frontend — Downloaded Media Library

Page to browse all downloaded/cached video files with metadata.

---

#### [NEW] [LibraryPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/LibraryPage.tsx)
- Tabbed view: "Downloads" and "Favourites" sub-sections
- Downloads tab: Fetches `/api/stream/files` and displays as grid
- Shows file name, size, format badge (HEVC/x264)
- Click to play directly via `/api/stream/file/` endpoint
- Search/filter within downloaded files

#### [MODIFY] [backendService.ts](file:///d:/Stream-Server-Frontend/src/services/backendService.ts)
- Add `getDownloadedFiles()` method — calls `/api/stream/files`
- Add `getFileStreamUrl(filePath)` — constructs playable URL for cached files

---

### Component 6: Frontend — Anime & Cartoon Categories

TMDB-based filtering to segregate anime and cartoons from general content.

---

#### [MODIFY] [tmdbService.ts](file:///d:/Stream-Server-Frontend/src/services/tmdbService.ts)
- Add `getAnime(page)` — Fetches TV shows with `with_genres=16` and `with_origin_country=JP`
- Add `getCartoons(page)` — Fetches TV shows with `with_genres=16` and `without_origin_country=JP` (Western animation)
- Add `getPopularToday(type)` — Fetches today's trending for "Popular RN" section

#### [MODIFY] [useTMDB.ts](file:///d:/Stream-Server-Frontend/src/hooks/useTMDB.ts)
- Add `useAnime(page)` hook
- Add `useCartoons(page)` hook
- Add `usePopularToday()` hook

#### [NEW] [CategoryPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/CategoryPage.tsx)
- Reusable page for Movies, TV Shows, Anime, Cartoons
- Accepts `category` prop/param to determine content
- Infinite scroll or "Load More" pagination
- Filter/sort options (by rating, year, popularity)

#### [NEW] [PopularPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/PopularPage.tsx)
- "Popular Right Now" page showing today's trending content
- Grid of trending movies and TV shows
- Auto-refreshes daily

---

### Component 7: Frontend — Navigation Overhaul

Expanded navigation with all new sections.

---

#### [MODIFY] [Navbar.tsx](file:///d:/Stream-Server-Frontend/src/components/Navbar.tsx)
Desktop navigation updates:
- Add nav items: Home, Movies, TV Shows, Anime, Popular
- Add user avatar/login button on the right
- Shows user email initial or login icon based on auth state

#### [MODIFY] [MobileNav.tsx](file:///d:/Stream-Server-Frontend/src/components/MobileNav.tsx)
Mobile bottom nav updates:
- 5 tabs: Home, Search, Library, Favourites, Profile
- Library = Downloads page
- Profile = Auth/Settings combined

#### [MODIFY] [HomePage.tsx](file:///d:/Stream-Server-Frontend/src/pages/HomePage.tsx)
- Add new carousels: "Popular Right Now", "Anime", "Cartoons"
- Reorder: Continue Watching → Popular RN → Trending → Movies → TV Shows → Anime → Cartoons → Top Rated

#### [MODIFY] [types/index.ts](file:///d:/Stream-Server-Frontend/src/types/index.ts)
- Add auth types: `User`, `AuthResponse`, `LoginRequest`, `RegisterRequest`
- Add favorites types: `FavoriteItem`
- Add `DownloadedFile` type for library

---

### Component 8: Frontend — Settings Page Update

---

#### [MODIFY] [SettingsPage.tsx](file:///d:/Stream-Server-Frontend/src/pages/SettingsPage.tsx)
- Add "Account" section showing logged-in user email
- Add logout button
- Add change password option

---

## File Summary

### Backend (6 files)
| File | Action | Purpose |
|------|--------|---------|
| `src/database/database.js` | NEW | SQLite initialization + schema |
| `src/middleware/authMiddleware.js` | NEW | JWT auth middleware |
| `src/routes/authRoutes.js` | NEW | Register/Login/Profile endpoints |
| `src/routes/favoritesRoutes.js` | NEW | Favorites CRUD endpoints |
| `src/server.js` | MODIFY | Mount new routes + init DB |
| `package.json` | MODIFY | Add new dependencies |

### Frontend (14 files)
| File | Action | Purpose |
|------|--------|---------|
| `src/store/authStore.ts` | NEW | Auth state management |
| `src/store/favoritesStore.ts` | NEW | Favorites state management |
| `src/services/authService.ts` | NEW | Auth API calls |
| `src/services/favoritesService.ts` | NEW | Favorites API calls |
| `src/pages/AuthPage.tsx` | NEW | Login/Register UI |
| `src/pages/FavoritesPage.tsx` | NEW | Favorites grid page |
| `src/pages/LibraryPage.tsx` | NEW | Downloaded media library |
| `src/pages/CategoryPage.tsx` | NEW | Movies/TV/Anime/Cartoons page |
| `src/pages/PopularPage.tsx` | NEW | Popular right now page |
| `src/types/index.ts` | MODIFY | New type definitions |
| `src/App.tsx` | MODIFY | New routes |
| `src/components/Navbar.tsx` | MODIFY | Expanded desktop nav |
| `src/components/MobileNav.tsx` | MODIFY | Expanded mobile nav |
| `src/pages/HomePage.tsx` | MODIFY | New carousels |

## Verification Plan

### Automated Tests
1. **Backend auth**: `curl` test register → login → get profile → add favorite → list favorites
2. **Backend build**: `npm start` to verify server starts without errors
3. **Frontend build**: `npm run build` to verify TypeScript compilation
4. **Frontend dev**: `npm run dev` and manually test all new pages

### Manual Verification
- Register a new account and login
- Add/remove favorites and verify persistence
- Browse Downloaded files and play one
- Navigate through Movies, TV Shows, Anime, Cartoons categories
- Verify mobile bottom nav works correctly
- Test auth flow: logout → restricted actions show login prompt
