import '../core/network/dio_clients.dart';
import '../models/favorite.dart';
import '../models/media.dart';

class FavoritesService {
  final _dio = ApiClients.instance.backend;

  Future<List<FavoriteItem>> getFavorites() async {
    final res = await _dio.get('/api/favorites');
    return (((res.data as Map)['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FavoriteItem.fromJson)
        .toList();
  }

  Future<void> addFavorite(MediaItem item, {String? category}) async {
    await _dio.post('/api/favorites', data: {
      'media_id': item.id,
      'media_type': item.mediaType,
      'category': category,
      'title': item.title,
      'poster_path': item.posterPath,
      'backdrop_path': item.backdropPath,
      'vote_average': item.voteAverage,
    });
  }

  Future<void> removeFavorite(int mediaId, String mediaType) async {
    await _dio.delete('/api/favorites/$mediaId/$mediaType');
  }
}

final favoritesService = FavoritesService();
