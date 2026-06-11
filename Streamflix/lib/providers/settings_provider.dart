import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage.dart';

class SettingsState {
  final String backendUrl;
  final String tmdbApiKey;
  final String theme; // 'dark' | 'oled'
  final String defaultQuality;
  final bool wolEnabled;
  final bool autoPlay;
  final String subtitleLanguage;

  const SettingsState({
    required this.backendUrl,
    required this.tmdbApiKey,
    required this.theme,
    required this.defaultQuality,
    required this.wolEnabled,
    required this.autoPlay,
    required this.subtitleLanguage,
  });

  bool get isConfigured => tmdbApiKey.isNotEmpty && backendUrl.isNotEmpty;

  SettingsState copyWith({
    String? backendUrl,
    String? tmdbApiKey,
    String? theme,
    String? defaultQuality,
    bool? wolEnabled,
    bool? autoPlay,
    String? subtitleLanguage,
  }) =>
      SettingsState(
        backendUrl: backendUrl ?? this.backendUrl,
        tmdbApiKey: tmdbApiKey ?? this.tmdbApiKey,
        theme: theme ?? this.theme,
        defaultQuality: defaultQuality ?? this.defaultQuality,
        wolEnabled: wolEnabled ?? this.wolEnabled,
        autoPlay: autoPlay ?? this.autoPlay,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  AppStorage get _s => AppStorage.instance;

  @override
  SettingsState build() => SettingsState(
        backendUrl: _s.backendUrl,
        tmdbApiKey: _s.tmdbApiKey,
        theme: _s.theme,
        defaultQuality: _s.defaultQuality,
        wolEnabled: _s.wolEnabled,
        autoPlay: _s.autoPlay,
        subtitleLanguage: _s.subtitleLanguage,
      );

  void setBackendUrl(String v) {
    _s.backendUrl = v;
    state = state.copyWith(backendUrl: v);
  }

  void setTmdbApiKey(String v) {
    _s.tmdbApiKey = v;
    state = state.copyWith(tmdbApiKey: v);
  }

  void setTheme(String v) {
    _s.theme = v;
    state = state.copyWith(theme: v);
  }

  void setDefaultQuality(String v) {
    _s.defaultQuality = v;
    state = state.copyWith(defaultQuality: v);
  }

  void setWolEnabled(bool v) {
    _s.wolEnabled = v;
    state = state.copyWith(wolEnabled: v);
  }

  void setAutoPlay(bool v) {
    _s.autoPlay = v;
    state = state.copyWith(autoPlay: v);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
