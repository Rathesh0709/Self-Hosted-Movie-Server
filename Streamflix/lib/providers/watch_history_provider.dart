import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage.dart';
import '../models/watch_history.dart';
import '../services/watch_history_service.dart';
import 'auth_provider.dart';

class WatchHistoryNotifier extends Notifier<List<WatchHistoryItem>> {
  Timer? _debounce;
  bool _syncing = false;

  @override
  List<WatchHistoryItem> build() =>
      AppStorage.instance.watchHistory.map(WatchHistoryItem.fromJson).toList();

  bool get _authed => ref.read(authProvider).isAuthenticated;

  void _persist() {
    AppStorage.instance.watchHistory = state.map((e) => e.toJson()).toList();
  }

  void _debounced(FutureOr<void> Function() fn, Duration delay) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => Future(() => fn()).catchError((_) {}));
  }

  void addToHistory(WatchHistoryItem item) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = item.copyWith(lastWatched: now);
    state = [updated, ...state.where((h) => h.id != item.id)].take(100).toList();
    _persist();
    if (_authed) watchHistoryService.upsertItem(updated).catchError((_) {});
  }

  void updateProgress(String id, double currentTime, double duration) {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            currentTime: currentTime,
            duration: duration,
            progress: duration > 0 ? currentTime / duration : 0,
            lastWatched: now,
          )
        else
          item,
    ];
    _persist();
    if (_authed) {
      _debounced(() async {
        final item = state.firstWhere((h) => h.id == id, orElse: () => state.first);
        await watchHistoryService.upsertItem(item);
      }, const Duration(seconds: 5));
    }
  }

  void updateItemMeta(String id, {String? title, String? posterPath, String? backdropPath}) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(title: title, posterPath: posterPath, backdropPath: backdropPath)
        else
          item,
    ];
    _persist();
  }

  void removeFromHistory(String id) {
    state = state.where((i) => i.id != id).toList();
    _persist();
    if (_authed) watchHistoryService.deleteItem(id).catchError((_) {});
  }

  void clearHistory() {
    state = [];
    _persist();
    if (_authed) watchHistoryService.clearAll().catchError((_) {});
  }

  WatchHistoryItem? getItem(String id) {
    for (final i in state) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Items 2%–90% watched, de-duped by normalized title, newest first.
  List<WatchHistoryItem> continueWatching() {
    final list = state.where((i) => i.progress > 0.02 && i.progress < 0.9).toList()
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    final seen = <String>{};
    return list.where((item) {
      final norm = item.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seen.contains(norm)) return false;
      seen.add(norm);
      return true;
    }).take(20).toList();
  }

  Future<void> syncWithServer() async {
    if (!_authed || _syncing) return;
    _syncing = true;
    try {
      final local = state;
      final merged = await watchHistoryService.syncHistory(local);
      final serverIds = merged.map((i) => i.id).toSet();
      final localOnly = local.where((i) => !serverIds.contains(i.id));
      final combined = [...merged, ...localOnly]
        ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
      state = combined.take(100).toList();
      _persist();
    } catch (_) {
      // local data intact
    } finally {
      _syncing = false;
    }
  }
}

final watchHistoryProvider =
    NotifierProvider<WatchHistoryNotifier, List<WatchHistoryItem>>(WatchHistoryNotifier.new);
