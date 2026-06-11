import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/storage.dart';
import '../../core/theme/app_theme.dart';
import '../../models/stream.dart';
import '../../models/watch_history.dart';
import '../../providers/player_provider.dart';
import '../../services/backend_service.dart';
import '../../services/subtitle_service.dart';
import '../../providers/watch_history_provider.dart';
import '../../widgets/glass.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});
  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final _focusNode = FocusNode();

  final _subs = <StreamSubscription>[];
  Timer? _hideTimer;
  Timer? _healthTimer;

  bool _controls = true;
  bool _buffering = true;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  double _lastVolume = 100;
  double _subDelay = 0; // subtitle sync offset, seconds
  double _lastReportedHistory = 0;
  StreamStatus? _health;
  bool _addedHistory = false;

  // Video sizing mode (mobile only) — cycles Fit → Stretch → Original.
  static const _fitModes = <(BoxFit, String, IconData)>[
    (BoxFit.contain, 'Fit', Icons.fit_screen_rounded),
    (BoxFit.fill, 'Stretch', Icons.aspect_ratio_rounded),
    (BoxFit.none, 'Original', Icons.crop_original_rounded),
  ];
  int _fitIndex = 0;
  BoxFit get _fit => _fitModes[_fitIndex].$1;

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fitModes.length);
    final label = _fitModes[_fitIndex].$2;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Video: $label'), duration: const Duration(milliseconds: 900)),
    );
    _resetHideTimer();
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final session = ref.read(playerProvider);
    if (session == null) {
      context.go('/home');
      return;
    }
    final url = backendService.resolveBackendUrl(session.streamUrl);
    // The backend serves MKV/HEVC as an HLS playlist whose segments are fetched
    // over http. libmpv's lavf HLS demuxer refuses to load http child segments
    // unless the protocol whitelist permits them — without this the playlist
    // loads but no segments do (0:00 duration, black screen) on Android/desktop.
    final platform = _player.platform;
    if (!kIsWeb && platform is NativePlayer) {
      try {
        final p = platform as dynamic;
        await p.setProperty(
          'demuxer-lavf-o',
          'protocol_whitelist=[file,http,https,tcp,tls,crypto,data,httpproxy]',
        );
        await p.setProperty('network-timeout', '60');
      } catch (_) {}
    }
    _player.open(Media(url));
    _player.play();

    _subs.add(
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }),
    );
    _subs.add(
      _player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }),
    );
    _subs.add(
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d);
        if (!_addedHistory && d.inSeconds > 0) {
          _addHistory();
          final saved = AppStorage.instance.playbackPosition(_progressKey(session));
          if (saved != null && saved > 5) {
            _player.seek(Duration(seconds: saved.toInt()));
          }
        }
      }),
    );
    _subs.add(_player.stream.position.listen(_onPosition));

    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final h = await backendService.getStreamHealth(session.streamId);
      if (mounted && h != null) setState(() => _health = h);
    });

    _resetHideTimer();
  }

  void _addHistory() {
    if (_addedHistory) return;
    _addedHistory = true;
    final session = ref.read(playerProvider)!;
    final m = session.media;
    ref
        .read(watchHistoryProvider.notifier)
        .addToHistory(
          WatchHistoryItem(
            id: '${m.mediaType}-${m.id}',
            mediaId: m.id,
            mediaType: m.mediaType,
            title: m.title,
            posterPath: m.posterPath,
            backdropPath: m.backdropPath,
            progress: 0.03,
            streamId: session.streamId,
            streamUrl: session.streamUrl,
            magnetURI: session.magnetURI,
            fileIdx: session.fileIdx,
            lastWatched: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// Position updates only touch LOCAL history. We must NOT hit the backend
  /// /seek endpoint here — doing so re-prioritises torrent pieces and starves
  /// the live playhead, freezing the stream.
  void _onPosition(Duration p) {
    if (mounted) setState(() => _position = p);
    final session = ref.read(playerProvider);
    if (session == null || _duration.inSeconds <= 0) return;
    final secs = p.inSeconds.toDouble();
    if ((secs - _lastReportedHistory).abs() >= 3) {
      _lastReportedHistory = secs;
      ref
          .read(watchHistoryProvider.notifier)
          .updateProgress(
            '${session.media.mediaType}-${session.media.id}',
            secs,
            _duration.inSeconds.toDouble(),
          );
      AppStorage.instance.setPlaybackPosition(_progressKey(session), secs);
    }
  }

  /// Per-playback resume key. For TV/anime it includes season+episode so each
  /// episode of a show keeps its own resume position instead of sharing one.
  String _progressKey(PlayerSession s) {
    if (s.season != null && s.episode != null) {
      return '${s.media.id}_s${s.season}e${s.episode}';
    }
    return '${s.media.id}';
  }

  /// Tell the backend the user seeked, so it re-prioritises pieces around the
  /// new position. Called ONLY on explicit seeks (skip buttons / slider drag).
  void _notifySeek() {
    final session = ref.read(playerProvider);
    if (session != null) backendService.reportSeek(session.streamId, 0);
  }

  void _resetHideTimer() {
    if (!_controls && mounted) setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    final target = (_position.inSeconds + seconds).clamp(
      0,
      _duration.inSeconds == 0 ? 1 << 31 : _duration.inSeconds,
    );
    _player.seek(Duration(seconds: target));
    _notifySeek();
    _resetHideTimer();
  }

  void _setVolume(double v) {
    _player.setVolume(v.clamp(0, 100));
    _resetHideTimer();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastVolume = _volume;
      _setVolume(0);
    } else {
      _setVolume(_lastVolume <= 0 ? 100 : _lastVolume);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _healthTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _focusNode.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    _resetHideTimer();
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playerProvider);
    if (session == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Video(
          controller: _controller,
          fit: _fit,
          controls: (state) =>
              _overlay(session.media.title, session.media.imdbId),
        ),
      ),
    );
  }

  Widget _overlay(String title, String? imdbId) {
    return Builder(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_buffering)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_controls,
                child: _controlsLayer(ctx, title, imdbId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlsLayer(BuildContext ctx, String title, String? imdbId) {
    return Stack(
      children: [
        // Top gradient bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const Text(
                          'NOW STREAMING',
                          style: TextStyle(
                            color: AppColors.mutedForeground,
                            fontSize: 9,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_health != null) _healthChip(_health!),
                ],
              ),
            ),
          ),
        ),
        // Center transport
        Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _circleBtn(Icons.replay_10_rounded, () => _seekRelative(-10), 34),
              const SizedBox(width: 30),
              _circleBtn(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                () => _player.playOrPause(),
                48,
                primary: true,
              ),
              const SizedBox(width: 30),
              _circleBtn(Icons.forward_10_rounded, () => _seekRelative(10), 34),
            ],
          ),
        ),
        // Bottom control bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seek bar
                  Row(
                    children: [
                      Text(
                        _fmt(_position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.primary,
                          ),
                          child: Slider(
                            value: _position.inSeconds
                                .clamp(
                                  0,
                                  _duration.inSeconds == 0
                                      ? 1
                                      : _duration.inSeconds,
                                )
                                .toDouble(),
                            max: _duration.inSeconds == 0
                                ? 1
                                : _duration.inSeconds.toDouble(),
                            onChanged: (v) {
                              setState(
                                () => _position = Duration(seconds: v.toInt()),
                              );
                              _resetHideTimer();
                            },
                            onChangeEnd: (v) {
                              _player.seek(Duration(seconds: v.toInt()));
                              _notifySeek();
                            },
                          ),
                        ),
                      ),
                      Text(
                        _fmt(_duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  // Buttons row
                  Row(
                    children: [
                      _barIcon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        () => _player.playOrPause(),
                      ),
                      _barIcon(
                        _volume <= 0
                            ? Icons.volume_off_rounded
                            : _volume < 50
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                        _toggleMute,
                      ),
                      SizedBox(
                        width: 90,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _volume.clamp(0, 100),
                            max: 100,
                            onChanged: _setVolume,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Video sizing cycle — phone only (PC/TV already map the
                      // resolution correctly, so the control is hidden there).
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android &&
                          MediaQuery.sizeOf(ctx).shortestSide < 600)
                        _barIcon(_fitModes[_fitIndex].$3, _cycleFit),
                      _barIcon(
                        Icons.closed_caption_rounded,
                        () => _showSubtitles(imdbId, title),
                      ),
                      PopupMenuButton<double>(
                        tooltip: 'Speed',
                        icon: const Icon(
                          Icons.speed_rounded,
                          color: Colors.white,
                        ),
                        color: AppColors.navyElevated,
                        onSelected: (r) {
                          _player.setRate(r);
                          _resetHideTimer();
                        },
                        itemBuilder: (_) => [
                          for (final r in [0.5, 1.0, 1.25, 1.5, 2.0])
                            PopupMenuItem(value: r, child: Text('${r}x')),
                        ],
                      ),
                      _barIcon(
                        Icons.fullscreen_rounded,
                        () => toggleFullscreen(ctx),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _barIcon(IconData icon, VoidCallback onTap) => IconButton(
    icon: Icon(icon, color: Colors.white),
    iconSize: 24,
    onPressed: onTap,
  );

  Widget _healthChip(StreamStatus h) {
    final color = switch (h.health) {
      'excellent' => const Color(0xFF34D399),
      'good' => AppColors.accent,
      'fair' => const Color(0xFFFBBF24),
      _ => const Color(0xFFF87171),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(right: 4, top: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${(h.downloadSpeed / 1024 / 1024).toStringAsFixed(1)} MB/s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(
    IconData icon,
    VoidCallback onTap,
    double size, {
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(primary ? 16 : 12),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: primary ? null : Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _showSubtitles(String? imdbId, String title) async {
    final session = ref.read(playerProvider)!;
    showGeneralDialog(
      context: context,
      barrierLabel: 'subtitles',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => Material(
        type: MaterialType.transparency,
        child: _SubtitlePanel(
          streamId: session.streamId,
          imdbId: imdbId,
          title: title,
          season: session.season,
          episode: session.episode,
          initialDelay: _subDelay,
          onOff: () {
            _player.setSubtitleTrack(SubtitleTrack.no());
            Navigator.pop(context);
          },
          onSelect: (entry) async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            navigator.pop();
            try {
              // Load the VTT ourselves and pass it as data (not a cross-origin
              // URL) so it actually loads on web as well as native.
              final content = await subtitleService.fetchContent(entry.url);
              if (content != null && content.trimLeft().startsWith('WEBVTT')) {
                await _player.setSubtitleTrack(
                  SubtitleTrack.data(content, title: entry.label),
                );
              } else {
                // Fall back to letting the player fetch the URL directly.
                await _player.setSubtitleTrack(
                  SubtitleTrack.uri(entry.url, title: entry.label),
                );
              }
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Subtitle failed to load: $e')),
              );
            }
          },
          onSync: _setSubtitleDelay,
          onUpload: () async {
            final navigator = Navigator.of(context);
            const group = XTypeGroup(
              label: 'subtitles',
              extensions: ['srt', 'vtt'],
            );
            final file = await openFile(acceptedTypeGroups: [group]);
            if (file != null) {
              var content = await file.readAsString();
              // Web `<track>` only parses WebVTT; convert SRT so uploads render.
              if (!content.trimLeft().startsWith('WEBVTT')) {
                content = 'WEBVTT\n\n${content.replaceAll(RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'), r'$1.$2')}';
              }
              await _player.setSubtitleTrack(
                SubtitleTrack.data(content, title: 'Uploaded'),
              );
            }
            navigator.pop();
          },
        ),
      ),
      transitionBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Shift the active subtitle track timing via mpv's `sub-delay` property.
  /// Native-only — the web (libmpv-less) backend has no `setProperty`.
  void _setSubtitleDelay(double seconds) {
    _subDelay = seconds;
    if (kIsWeb) return;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      (platform as dynamic).setProperty('sub-delay', seconds.toString());
    }
  }
}

/// Glass subtitle panel anchored bottom-right with Server / Torrent / Sync
/// tabs — 1:1 with React's SubtitleMenu.tsx.
class _SubtitlePanel extends StatefulWidget {
  final String streamId;
  final String? imdbId;
  final String title;
  final int? season;
  final int? episode;
  final double initialDelay;
  final VoidCallback onOff;
  final void Function(SubtitleEntry) onSelect;
  final void Function(double) onSync;
  final VoidCallback onUpload;
  const _SubtitlePanel({
    required this.streamId,
    required this.imdbId,
    required this.title,
    required this.season,
    required this.episode,
    required this.initialDelay,
    required this.onOff,
    required this.onSelect,
    required this.onSync,
    required this.onUpload,
  });

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<_SubtitlePanel> {
  int _tab = 0; // 0 server, 1 torrent, 2 sync
  List<SubtitleEntry> _torrent = [];
  List<SubtitleEntry> _online = [];
  bool _loadingServer = true;
  bool _loadingTorrent = true;
  late double _delay = widget.initialDelay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    backendService.getTorrentSubtitles(widget.streamId).then((t) {
      if (mounted) {
        setState(() {
          _torrent = t;
          _loadingTorrent = false;
        });
      }
    });
    subtitleService
        .search(
          imdbId: widget.imdbId,
          query: widget.imdbId == null ? widget.title : null,
          season: widget.season,
          episode: widget.episode,
        )
        .then((o) {
      if (mounted) {
        setState(() {
          _online = o;
          _loadingServer = false;
        });
      }
    });
  }

  void _adjust(double delta) {
    setState(() => _delay = double.parse((_delay + delta).toStringAsFixed(1)));
    widget.onSync(_delay);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Stack(
      children: [
        // Tap-away barrier
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          right: 16 + pad.right,
          bottom: 90 + pad.bottom,
          child: Glass.strong(
            radius: 20,
            fill: Colors.black.withValues(alpha: 0.8),
            borderColor: Colors.white.withValues(alpha: 0.1),
            shadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 40, spreadRadius: -8),
            ],
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Subtitles',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded,
                                size: 18, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tabs
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _tabBtn('Server', 0),
                        _tabBtn('Torrent', 1),
                        _tabBtn('Sync', 2),
                      ],
                    ),
                  ),
                  // Content
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: _content(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabBtn(String label, int i) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.primary : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (_tab) {
      case 1:
        return _torrentTab();
      case 2:
        return _syncTab();
      default:
        return _serverTab();
    }
  }

  Widget _serverTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Upload local subtitle
        OutlinedButton.icon(
          onPressed: widget.onUpload,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: const Icon(Icons.upload_rounded, size: 16),
          label: const Text('Upload Local Subtitle'),
        ),
        const SizedBox(height: 8),
        // Off option
        _subRow(
          icon: Icons.subtitles_off_rounded,
          label: 'Off (no subtitles)',
          onTap: widget.onOff,
          trailingIcon: Icons.block_rounded,
        ),
        const SizedBox(height: 6),
        if (_loadingServer)
          const _Spinner()
        else if (_online.isEmpty)
          const _NoneText('No subtitles found on server')
        else
          for (final s in _online) ...[
            _subRow(
              label: s.label,
              sub: s.downloads != null ? '${s.downloads} downloads' : null,
              onTap: () => widget.onSelect(s),
              trailingIcon: Icons.download_rounded,
              accentTrailing: true,
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  Widget _torrentTab() {
    if (_loadingTorrent) return const _Spinner();
    if (_torrent.isEmpty) {
      return const _NoneText('No subtitle files detected in torrent');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in _torrent) ...[
          _subRow(
            icon: Icons.storage_rounded,
            label: s.label,
            onTap: () => widget.onSelect(s),
            trailingIcon: Icons.check_rounded,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _syncTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          const Text(
            'Subtitle Delay Offset',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          Text(
            '${_delay > 0 ? '+' : ''}${_delay.toStringAsFixed(1)}s',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundBtn(Icons.remove_rounded, () => _adjust(-0.5)),
              const SizedBox(width: 16),
              const Text(
                'ADJUST',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(width: 16),
              _roundBtn(Icons.add_rounded, () => _adjust(0.5)),
            ],
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Adjusts the timing of the currently active subtitle track. Make sure a subtitle is playing first.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _subRow({
    IconData? icon,
    required String label,
    String? sub,
    required VoidCallback onTap,
    required IconData trailingIcon,
    bool accentTrailing = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentTrailing
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
              ),
              child: Icon(
                trailingIcon,
                size: 16,
                color: accentTrailing ? AppColors.primary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
}

class _NoneText extends StatelessWidget {
  final String text;
  const _NoneText(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
      );
}
