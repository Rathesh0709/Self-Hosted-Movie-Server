import '../core/network/dio_clients.dart';
import '../models/watch_history.dart';

class WatchHistoryService {
  final _dio = ApiClients.instance.backend;

  Future<List<WatchHistoryItem>> getHistory() async {
    final res = await _dio.get('/api/watch-history');
    return (((res.data as Map)['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(WatchHistoryItem.fromJson)
        .toList();
  }

  Future<void> upsertItem(WatchHistoryItem item) async {
    await _dio.put('/api/watch-history', data: item.toJson());
  }

  Future<void> deleteItem(String watchId) async {
    await _dio.delete('/api/watch-history/${Uri.encodeComponent(watchId)}');
  }

  Future<void> clearAll() async {
    await _dio.delete('/api/watch-history/all');
  }

  Future<List<WatchHistoryItem>> syncHistory(List<WatchHistoryItem> items) async {
    final res = await _dio.post('/api/watch-history/sync',
        data: {'items': items.map((e) => e.toJson()).toList()});
    return (((res.data as Map)['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(WatchHistoryItem.fromJson)
        .toList();
  }
}

final watchHistoryService = WatchHistoryService();
