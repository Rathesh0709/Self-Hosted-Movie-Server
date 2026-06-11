import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../core/storage.dart';
import 'backend_service.dart';

/// Wake-on-LAN helper (port of wakeService.ts). Best-effort HTTP wake to the
/// WoL agent, then polls backend health until it responds.
class WakeService {
  /// Auto-wake used before streaming/downloading. No-op when WoL is disabled or
  /// the server already responds. Fires the wake then waits for health.
  Future<void> wakeServer() async {
    if (!AppStorage.instance.wolEnabled) return;
    final url = AppStorage.instance.backendUrl;
    if (await backendService.testConnection(url)) return;
    await sendWake();
    await waitForServer();
  }

  /// Manual wake (Settings button). Always fires regardless of the toggle and
  /// reports whether the server came back online.
  Future<bool> wakeAndWait({int maxRetries = 20}) async {
    final url = AppStorage.instance.backendUrl;
    if (await backendService.testConnection(url)) return true;
    await sendWake();
    return waitForServer(maxRetries);
  }

  /// Sleep the media server via the backend power endpoint. Returns whether the
  /// command was accepted.
  Future<bool> sleepServer() async {
    final url = AppStorage.instance.backendUrl;
    try {
      final res = await Dio().post(
        '$url/api/power/sleep',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = res.data;
      return data is Map && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendWake() async {
    try {
      await Dio().get(kWakeUrl,
          options: Options(receiveTimeout: const Duration(seconds: 5)));
    } catch (_) {
      // Expected to fail/timeout; the request may still reach the agent.
    }
  }

  Future<bool> waitForServer([int maxRetries = 20]) async {
    final url = AppStorage.instance.backendUrl;
    for (var i = 0; i < maxRetries; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (await backendService.testConnection(url)) return true;
    }
    return false;
  }
}

final wakeService = WakeService();
