import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/favorite.dart';
import '../models/media.dart';
import '../services/favorites_service.dart';
import 'auth_provider.dart';

class FavoritesNotifier extends Notifier<List<FavoriteItem>> {
  @override
  List<FavoriteItem> build() => const [];

  bool get _authed => ref.read(authProvider).isAuthenticated;

  Future<void> fetchFavorites() async {
    if (!_authed) return;
    try {
      state = await favoritesService.getFavorites();
    } catch (_) {}
  }

  Future<void> addFavorite(MediaItem item, {String? category}) async {
    final optimistic = FavoriteItem(
      mediaId: item.id,
      mediaType: item.mediaType,
      category: category,
      title: item.title,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      voteAverage: item.voteAverage,
    );
    state = [
      optimistic,
      ...state.where((i) => !(i.mediaId == item.id && i.mediaType == item.mediaType)),
    ];
    try {
      await favoritesService.addFavorite(item, category: category);
    } catch (_) {}
  }

  Future<void> removeFavorite(int mediaId, String mediaType) async {
    state = state.where((i) => !(i.mediaId == mediaId && i.mediaType == mediaType)).toList();
    try {
      await favoritesService.removeFavorite(mediaId, mediaType);
    } catch (_) {}
  }

  bool isFavorite(int mediaId, String mediaType) =>
      state.any((i) => i.mediaId == mediaId && i.mediaType == mediaType);

  void clear() => state = const [];
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<FavoriteItem>>(FavoritesNotifier.new);
