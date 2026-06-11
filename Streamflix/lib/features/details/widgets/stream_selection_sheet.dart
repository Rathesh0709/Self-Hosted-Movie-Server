import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/media.dart';
import '../../../models/stream.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/streams_provider.dart';
import '../../../services/backend_service.dart';
import '../../../services/torrentio_service.dart';
import '../../../services/wake_service.dart';
import '../../../widgets/glass.dart';
import '../../../widgets/loading_skeleton.dart';
import 'stream_card.dart';

/// Show the stream/download source selector as a centered glass dialog —
/// 1:1 with React's StreamSelectionModal (Dialog + `.glass` + X close).
Future<void> showStreamSelection(
  BuildContext context, {
  required MediaItem media,
  required String imdbId,
  String mode = 'stream', // 'stream' | 'download'
  int? season,
  int? episode,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'streams',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => Material(
      type: MaterialType.transparency,
      child: _StreamDialog(
        media: media,
        imdbId: imdbId,
        mode: mode,
        season: season,
        episode: episode,
      ),
    ),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _StreamDialog extends ConsumerStatefulWidget {
  final MediaItem media;
  final String imdbId;
  final String mode;
  final int? season;
  final int? episode;
  const _StreamDialog({
    required this.media,
    required this.imdbId,
    required this.mode,
    this.season,
    this.episode,
  });

  @override
  ConsumerState<_StreamDialog> createState() => _StreamDialogState();
}

class _StreamDialogState extends ConsumerState<_StreamDialog> {
  String? _connectingHash;
  bool _waking = false;

  Future<void> _onSelect(ParsedStream stream) async {
    final backendUrl = ref.read(settingsProvider).backendUrl;
    final wol = ref.read(settingsProvider).wolEnabled;

    final online = await backendService.testConnection(backendUrl);
    if (!online && wol) {
      setState(() => _waking = true);
      await wakeService.wakeServer();
      setState(() => _waking = false);
    }

    setState(() => _connectingHash = stream.infoHash);
    final magnet = TorrentioService.magnetUri(stream);

    try {
      var fileIdx = stream.fileIdx;
      if (fileIdx == null && widget.episode != null) {
        final res = await backendService.resolveAnimeEpisode(magnet, widget.episode!);
        if (res['success'] == true) {
          fileIdx = res['fileIdx'] as int?;
        } else {
          _toast('Failed to resolve episode file from the torrent batch.');
          setState(() => _connectingHash = null);
          return;
        }
      }

      if (widget.mode == 'download') {
        final res = await backendService.downloadTorrent(magnet, fileIdx: fileIdx);
        if (mounted) Navigator.of(context).pop();
        _toast(res['success'] == true
            ? 'Download started on server. Track it in Library.'
            : 'Failed to start download.');
        return;
      }

      final res = await backendService.startStream(magnet, fileIdx: fileIdx);
      if (res.success && res.streamId.isNotEmpty) {
        final playable = backendService.playableUrl(res.stream);
        ref.read(playerProvider.notifier).setStream(
              res.streamId,
              playable,
              widget.media,
              magnetURI: magnet,
              fileIdx: fileIdx,
              season: widget.season,
              episode: widget.episode,
            );
        if (!mounted) return;
        Navigator.of(context).pop();
        context.push('/player/${res.streamId}');
      } else {
        _toast('Backend failed to create a stream session.');
      }
    } catch (e) {
      _toast('Could not connect to the backend server.');
    } finally {
      if (mounted) setState(() => _connectingHash = null);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final query = StreamQuery(widget.media, widget.imdbId,
        season: widget.season, episode: widget.episode);
    final streams = ref.watch(streamsProvider(query));
    final busy = _connectingHash != null || _waking;
    final isDownload = widget.mode == 'download';
    final sub = widget.season != null && widget.episode != null
        ? '${widget.media.title} — Season ${widget.season}, Episode ${widget.episode}'
        : widget.media.title;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Glass.strong(
            radius: 24,
            shadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 60, spreadRadius: -10),
            ],
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isDownload
                                      ? 'Select Torrent Source (Download)'
                                      : 'Select Torrent Stream',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.mutedForeground,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _IconBtn(
                            icon: Icons.refresh_rounded,
                            onTap: busy
                                ? null
                                : () => ref.invalidate(streamsProvider(query)),
                          ),
                          const SizedBox(width: 8),
                          _IconBtn(
                            icon: Icons.close_rounded,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    // List
                    Flexible(
                      child: streams.when(
                        loading: () =>
                            _Loading(indian: widget.media.originCountry.contains('IN')),
                        error: (_, _) => const _Empty(
                          icon: Icons.cloud_off_rounded,
                          title: 'Connection Failed',
                          subtitle:
                              'Could not retrieve stream lists from indexers. Check your connection or retry.',
                        ),
                        data: (list) {
                          if (list.isEmpty) {
                            return const _Empty(
                              icon: Icons.search_off_rounded,
                              title: 'No torrent stream pools found.',
                              subtitle:
                                  'No seeders or available file indexes match this reference on the indexers currently.',
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => StreamCard(
                              stream: list[i],
                              disabled: busy,
                              onTap: () => _onSelect(list[i]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // Connecting / waking overlay
                if (busy)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.85),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: AppColors.glow(blur: 20, alpha: 0.5),
                              ),
                              child: const CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 3,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _waking
                                  ? 'Waking Media Server...'
                                  : isDownload
                                      ? 'Adding Server Download...'
                                      : 'Starting Torrent Stream...',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _waking
                                  ? 'Sending wake signal via Tailscale/WoL. Please wait up to 60 seconds.'
                                  : 'Backend is fetching piece maps, resolving torrent metadata, and joining the swarm. Grab some popcorn!',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.mutedForeground,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(icon, size: 18, color: Colors.white70),
          ),
        ),
      );
}

class _Loading extends StatelessWidget {
  final bool indian;
  const _Loading({this.indian = false});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    indian
                        ? 'Scraping Torrentio, TorrentsDB & TamilMV…\nTamilMV scrapes the site live — this can take up to a minute.'
                        : 'Scraping streams from Torrentio, TorrentsDB & Prowlarr...',
                    style: const TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerBox(height: 92, radius: 14),
              ),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Empty({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppColors.mutedForeground),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
}
