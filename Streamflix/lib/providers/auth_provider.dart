import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthState {
  final User? user;
  final String? token;
  bool get isAuthenticated => token != null && token!.isNotEmpty;
  const AuthState({this.user, this.token});
}

class AuthNotifier extends Notifier<AuthState> {
  AppStorage get _s => AppStorage.instance;

  @override
  AuthState build() {
    final u = _s.authUser;
    return AuthState(
      token: _s.authToken,
      user: u == null ? null : User.fromJson(u),
    );
  }

  void _persist(String token, User user) {
    _s.authToken = token;
    _s.authUser = user.toJson();
    state = AuthState(token: token, user: user);
  }

  Future<void> login(String email, String password) async {
    final res = await authService.login(email, password);
    _persist(res.token, res.user);
  }

  Future<void> register(String email, String password) async {
    final res = await authService.register(email, password);
    _persist(res.token, res.user);
  }

  void logout() {
    _s.authToken = null;
    _s.authUser = null;
    state = const AuthState();
  }

  /// Verify token; only clear on explicit 401/403 (keep session on transient
  /// network errors — mirrors authStore.loadUser).
  Future<void> loadUser() async {
    if (state.token == null) return;
    try {
      final user = await authService.getProfile();
      _s.authUser = user.toJson();
      state = AuthState(token: state.token, user: user);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        logout();
      }
    } catch (_) {/* keep session */}
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
