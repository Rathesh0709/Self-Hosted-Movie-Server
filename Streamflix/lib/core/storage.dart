import 'dart:convert';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'constants.dart';

/// Synchronous, app-wide key/value store backed by a single Hive box.
/// Mirrors the React app's mix of zustand-persist + localStorage so the
/// dio interceptors can read settings/token synchronously.
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  late Box _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('streamflix');
  }

  // ---- generic helpers ----
  T _get<T>(String k, T fallback) => (_box.get(k) as T?) ?? fallback;

  // ---- settings (DEFAULT_SETTINGS) ----
  String get backendUrl => _get('backendUrl', kDefaultBackendUrl);
  set backendUrl(String v) => _box.put('backendUrl', v);

  String get tmdbApiKey => _get('tmdbApiKey', '');
  set tmdbApiKey(String v) => _box.put('tmdbApiKey', v);

  String get theme => _get('theme', 'dark'); // 'dark' | 'oled'
  set theme(String v) => _box.put('theme', v);

  String get defaultQuality => _get('defaultQuality', '1080p');
  set defaultQuality(String v) => _box.put('defaultQuality', v);

  bool get wolEnabled => _get('wolEnabled', true);
  set wolEnabled(bool v) => _box.put('wolEnabled', v);

  bool get autoPlay => _get('autoPlay', true);
  set autoPlay(bool v) => _box.put('autoPlay', v);

  String get subtitleLanguage => _get('subtitleLanguage', 'en');
  set subtitleLanguage(String v) => _box.put('subtitleLanguage', v);

  // ---- auth ----
  String? get authToken => _box.get('authToken') as String?;
  set authToken(String? v) =>
      v == null ? _box.delete('authToken') : _box.put('authToken', v);

  Map<String, dynamic>? get authUser {
    final raw = _box.get('authUser') as String?;
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  set authUser(Map<String, dynamic>? v) =>
      v == null ? _box.delete('authUser') : _box.put('authUser', jsonEncode(v));

  // ---- watch history (list of json maps) ----
  List<Map<String, dynamic>> get watchHistory {
    final raw = _box.get('watchHistory') as String?;
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  set watchHistory(List<Map<String, dynamic>> v) => _box.put('watchHistory', jsonEncode(v));

  // ---- last player session (playerStore partialize) ----
  Map<String, dynamic>? get playerSession {
    final raw = _box.get('playerSession') as String?;
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  set playerSession(Map<String, dynamic>? v) =>
      v == null ? _box.delete('playerSession') : _box.put('playerSession', jsonEncode(v));

  /// Persisted playback position per playback key. For TV the key includes the
  /// season+episode so different episodes of the same show don't share a resume
  /// position (replaces `video-progress-<id>`).
  double? playbackPosition(String key) =>
      (_box.get('progress_$key') as num?)?.toDouble();
  void setPlaybackPosition(String key, double secs) => _box.put('progress_$key', secs);
}
