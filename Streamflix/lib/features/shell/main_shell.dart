import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass.dart';

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  const _Dest(this.label, this.icon, this.selectedIcon, this.route);
}

/// Full destination set (desktop top bar + TV rail).
const _full = [
  _Dest('Home', Icons.home_outlined, Icons.home_rounded, '/home'),
  _Dest('Search', Icons.search_outlined, Icons.search_rounded, '/search'),
  _Dest('Movies', Icons.movie_outlined, Icons.movie_rounded, '/movies'),
  _Dest('TV Shows', Icons.tv_outlined, Icons.tv_rounded, '/tvshows'),
  _Dest('Anime', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, '/anime'),
  _Dest('Popular', Icons.local_fire_department_outlined, Icons.local_fire_department_rounded,
      '/popular'),
  _Dest('Library', Icons.video_library_outlined, Icons.video_library_rounded, '/library'),
  _Dest('Favorites', Icons.favorite_outline_rounded, Icons.favorite_rounded, '/favorites'),
];

/// Condensed set for the mobile bottom bar.
const _mobile = [
  _Dest('Home', Icons.home_outlined, Icons.home_rounded, '/home'),
  _Dest('Search', Icons.search_outlined, Icons.search_rounded, '/search'),
  _Dest('Library', Icons.video_library_outlined, Icons.video_library_rounded, '/library'),
  _Dest('Favorites', Icons.favorite_outline_rounded, Icons.favorite_rounded, '/favorites'),
];

/// Responsive navigation shell:
///  - **Mobile** (shortestSide < 600): bottom navigation bar
///  - **Desktop / PC** (wide, pointer): top navigation bar
///  - **TV** (Android-native, large landscape): rich left sidebar (D-pad friendly)
class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  bool _isTV(Size size) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      size.shortestSide >= 600 &&
      size.width >= size.height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final isAuthed = ref.watch(authProvider).isAuthenticated;
    final size = MediaQuery.sizeOf(context);

    final profileRoute = isAuthed ? '/settings' : '/auth';
    final profileActive = location.startsWith('/settings') || location.startsWith('/auth');

    if (_isTV(size)) {
      return Scaffold(
        body: Row(
          children: [
            _TvRail(
              location: location,
              isAuthed: isAuthed,
              profileRoute: profileRoute,
              profileActive: profileActive,
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    if (size.shortestSide < 600) {
      return _mobileShell(context, location, profileRoute, profileActive, isAuthed);
    }

    return _desktopShell(context, location, profileRoute, profileActive, isAuthed);
  }

  // ---------------- Mobile: bottom bar ----------------
  Widget _mobileShell(BuildContext context, String location, String profileRoute,
      bool profileActive, bool isAuthed) {
    var selected = _mobile.indexWhere((d) => location.startsWith(d.route));
    if (profileActive) selected = _mobile.length;
    if (selected < 0) selected = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) =>
            context.go(i < _mobile.length ? _mobile[i].route : profileRoute),
        destinations: [
          for (final d in _mobile)
            NavigationDestination(
                icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          NavigationDestination(
            icon: Icon(isAuthed ? Icons.settings_outlined : Icons.person_outline_rounded),
            selectedIcon: Icon(isAuthed ? Icons.settings_rounded : Icons.person_rounded),
            label: isAuthed ? 'Settings' : 'Profile',
          ),
        ],
      ),
    );
  }

  // ---------------- Desktop / PC: top bar ----------------
  Widget _desktopShell(BuildContext context, String location, String profileRoute,
      bool profileActive, bool isAuthed) {
    return Scaffold(
      body: Column(
        children: [
          _DesktopTopBar(
            location: location,
            isAuthed: isAuthed,
            profileRoute: profileRoute,
            profileActive: profileActive,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ============================================================
// Desktop top navigation bar
// ============================================================
class _DesktopTopBar extends StatelessWidget {
  final String location;
  final bool isAuthed;
  final String profileRoute;
  final bool profileActive;
  const _DesktopTopBar({
    required this.location,
    required this.isAuthed,
    required this.profileRoute,
    required this.profileActive,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
        children: [
          const _Brand(),
          const SizedBox(width: 24),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in _full)
                    _TopNavItem(
                      dest: d,
                      active: location.startsWith(d.route),
                      onTap: () => context.go(d.route),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SearchPill(onTap: () => context.go('/search')),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => context.go(profileRoute),
            borderRadius: BorderRadius.circular(999),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: profileActive
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.18),
              child: Icon(
                isAuthed ? Icons.person_rounded : Icons.person_outline_rounded,
                size: 20,
                color: profileActive ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}

class _TopNavItem extends StatelessWidget {
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;
  const _TopNavItem({required this.dest, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(active ? dest.selectedIcon : dest.icon,
                  size: 18, color: active ? AppColors.primary : AppColors.mutedForeground),
              const SizedBox(width: 8),
              Text(
                dest.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, size: 16, color: AppColors.mutedForeground),
            SizedBox(width: 8),
            Text('Search…',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.mutedForeground,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TV sidebar (rich, D-pad friendly)
// ============================================================
class _TvRail extends StatelessWidget {
  final String location;
  final bool isAuthed;
  final String profileRoute;
  final bool profileActive;
  const _TvRail({
    required this.location,
    required this.isAuthed,
    required this.profileRoute,
    required this.profileActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            Theme.of(context).colorScheme.surfaceContainer,
          ],
        ),
        border: const Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: _Brand(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final d in _full)
                    _RailItem(
                      dest: d,
                      active: location.startsWith(d.route),
                      onTap: () => context.go(d.route),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: _RailItem(
                dest: _Dest(
                  isAuthed ? 'Settings' : 'Profile',
                  isAuthed ? Icons.settings_outlined : Icons.person_outline_rounded,
                  isAuthed ? Icons.settings_rounded : Icons.person_rounded,
                  profileRoute,
                ),
                active: profileActive,
                onTap: () => context.go(profileRoute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;
  const _RailItem({required this.dest, required this.active, required this.onTap});

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: widget.onTap,
        autofocus: active,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryDim])
                : null,
            color: !active && _focused ? Colors.white.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(14),
            border: _focused && !active
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5)
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(active ? widget.dest.selectedIcon : widget.dest.icon,
                  size: 22, color: active ? Colors.white : AppColors.mutedForeground),
              const SizedBox(width: 14),
              Text(
                widget.dest.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Shared brand mark
// ============================================================
class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/home'),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 14),
              ],
            ),
            child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'STREAM',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              GradientText(
                'FLIX',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
