import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/watch_history_provider.dart';
import '../../services/auth_service.dart';
import '../../services/backend_service.dart';
import '../../services/freekeys.dart';
import '../../services/wake_service.dart';
import '../../widgets/glass.dart';
import '../../widgets/page_header.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _backendUrl;
  late final TextEditingController _tmdbKey;
  final _currentPw = TextEditingController();
  final _newPw = TextEditingController();

  String _conn = 'idle'; // idle | testing | success | failed
  bool _waking = false;
  bool _sleeping = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backendUrl = TextEditingController(text: s.backendUrl);
    _tmdbKey = TextEditingController(text: s.tmdbApiKey);
  }

  @override
  void dispose() {
    _backendUrl.dispose();
    _tmdbKey.dispose();
    _currentPw.dispose();
    _newPw.dispose();
    super.dispose();
  }

  void _save() {
    final n = ref.read(settingsProvider.notifier);
    n.setBackendUrl(_backendUrl.text.trim());
    n.setTmdbApiKey(_tmdbKey.text.trim());
    _toast('Settings saved');
  }

  Future<void> _test() async {
    setState(() => _conn = 'testing');
    final ok = await backendService.testConnection(_backendUrl.text.trim());
    setState(() => _conn = ok ? 'success' : 'failed');
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);

    return Column(
      children: [
        const PageHeader(title: 'Settings'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Streaming Server', Icons.dns_rounded, [
                TextField(
                  controller: _backendUrl,
                  decoration: const InputDecoration(
                    hintText: 'http://your-server:3000',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _connDot(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(switch (_conn) {
                        'testing' => 'Testing…',
                        'success' => 'Online',
                        'failed' => 'Offline / unreachable',
                        _ => 'Not tested',
                      }, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    OutlinedButton(
                      onPressed: _conn == 'testing' ? null : _test,
                      child: const Text('Test'),
                    ),
                  ],
                ),
              ]),
              _section('TMDB API Key', Icons.key_rounded, [
                TextField(
                  controller: _tmdbKey,
                  decoration: const InputDecoration(
                    hintText: 'TMDB v3 API key',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    _tmdbKey.text = freeTmdbKey();
                    _toast('Generated a free TMDB key');
                  },
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Auto-generate free key'),
                ),
              ]),
              _section('Appearance', Icons.palette_rounded, [
                _toggleRow(
                  'Deep Navy',
                  'OLED Pure Black',
                  settings.theme == 'oled',
                  (oled) => ref
                      .read(settingsProvider.notifier)
                      .setTheme(oled ? 'oled' : 'dark'),
                ),
              ]),
              _section('Default Quality', Icons.high_quality_rounded, [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in ['2160p', '1080p', '720p'])
                      ChoiceChip(
                        label: Text(q == '2160p' ? '4K' : q),
                        selected: settings.defaultQuality == q,
                        onSelected: (_) => ref
                            .read(settingsProvider.notifier)
                            .setDefaultQuality(q),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.navyElevated,
                      ),
                  ],
                ),
              ]),
              _section('Wake-on-LAN', Icons.power_settings_new_rounded, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-wake media server'),
                  subtitle: const Text(
                    'Sends a wake request automatically when you stream or '
                    'download and the server is offline.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  value: settings.wolEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setWolEnabled(v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _waking ? null : _wakePc,
                        icon: _waking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.power_rounded, size: 18),
                        label: Text(_waking ? 'Waking…' : 'Wake PC'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sleeping ? null : _sleepPc,
                        icon: _sleeping
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bedtime_rounded, size: 18),
                        label: Text(_sleeping ? 'Sleeping…' : 'Sleep PC'),
                      ),
                    ),
                  ],
                ),
              ]),
              if (auth.isAuthenticated)
                _section('Account', Icons.person_rounded, [
                  Text(
                    'Signed in as ${auth.user?.email ?? ''}',
                    style: const TextStyle(color: AppColors.mutedForeground),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _currentPw,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Current password',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPw,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'New password'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          if (_currentPw.text.isEmpty || _newPw.text.isEmpty) {
                            return;
                          }
                          try {
                            await authService.changePassword(
                              _currentPw.text,
                              _newPw.text,
                            );
                            _currentPw.clear();
                            _newPw.clear();
                            _toast('Password changed');
                          } catch (_) {
                            _toast('Failed to change password');
                          }
                        },
                        child: const Text('Change password'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.destructive,
                        ),
                        onPressed: () {
                          ref.read(authProvider.notifier).logout();
                          ref.read(favoritesProvider.notifier).clear();
                          context.go('/auth');
                        },
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ])
              else
                _section('Account', Icons.person_outline_rounded, [
                  FilledButton(
                    onPressed: () => context.push('/auth'),
                    child: const Text('Login / Register'),
                  ),
                ]),
              _section('Storage', Icons.delete_outline_rounded, [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.destructive.withValues(
                      alpha: 0.15,
                    ),
                    foregroundColor: AppColors.destructive,
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Clear watch history?'),
                        content: const Text(
                          'This removes all playback progress. Cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      ref.read(watchHistoryProvider.notifier).clearHistory();
                      _toast('Watch history cleared');
                    }
                  },
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Clear playback progress'),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save configuration'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _wakePc() async {
    setState(() => _waking = true);
    final ok = await wakeService.wakeAndWait();
    if (!mounted) return;
    setState(() {
      _waking = false;
      if (ok) _conn = 'success';
    });
    _toast(ok ? 'Server is online' : 'Wake sent — server still offline');
  }

  Future<void> _sleepPc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sleep media server?'),
        content: const Text(
          'The PC will suspend. Wake it again with Wake PC or by streaming.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sleep'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sleeping = true);
    final done = await wakeService.sleepServer();
    if (!mounted) return;
    setState(() => _sleeping = false);
    _toast(done ? 'Sleep command sent' : 'Failed to reach server');
  }

  Widget _connDot() {
    final color = switch (_conn) {
      'success' => const Color(0xFF34D399),
      'failed' => AppColors.destructive,
      'testing' => AppColors.accent,
      _ => AppColors.mutedForeground,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _toggleRow(
    String left,
    String right,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Row(
    children: [
      Expanded(
        child: GestureDetector(
          onTap: () => onChanged(false),
          child: _pill(left, !value),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GestureDetector(
          onTap: () => onChanged(true),
          child: _pill(right, value),
        ),
      ),
    ],
  );

  Widget _pill(String label, bool active) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: active ? AppColors.brandGradient : null,
      color: active ? null : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: active ? Colors.transparent : AppColors.border,
      ),
      boxShadow: active ? AppColors.glow(blur: 16, alpha: 0.3) : null,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: active ? Colors.white : AppColors.mutedForeground,
      ),
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) => Glass(
        margin: const EdgeInsets.only(bottom: 16),
        radius: 18,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
}
