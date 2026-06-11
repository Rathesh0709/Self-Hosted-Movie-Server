import 'package:go_router/go_router.dart';
import '../../features/auth/auth_page.dart';
import '../../features/category/category_page.dart';
import '../../features/details/details_page.dart';
import '../../features/favorites/favorites_page.dart';
import '../../features/home/home_page.dart';
import '../../features/library/library_page.dart';
import '../../features/player/player_page.dart';
import '../../features/search/search_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/splash/splash_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    ShellRoute(
      builder: (_, _, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomePage()),
        GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
        GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
        GoRoute(path: '/favorites', builder: (_, _) => const FavoritesPage()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        for (final c in ['movies', 'tvshows', 'anime', 'cartoons', 'popular'])
          GoRoute(path: '/$c', builder: (_, _) => CategoryPage(category: c)),
      ],
    ),
    GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
    GoRoute(
      path: '/movie/:id',
      builder: (_, s) => DetailsPage(mediaType: 'movie', id: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/tv/:id',
      builder: (_, s) => DetailsPage(mediaType: 'tv', id: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(path: '/player/:streamId', builder: (_, _) => const PlayerPage()),
  ],
);
