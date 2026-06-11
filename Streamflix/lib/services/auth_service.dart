import '../core/network/dio_clients.dart';
import '../models/user.dart';

class AuthService {
  final _dio = ApiClients.instance.backend;

  Future<AuthResponse> register(String email, String password) async {
    final res = await _dio.post('/api/auth/register', data: {'email': email, 'password': password});
    return AuthResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AuthResponse> login(String email, String password) async {
    final res = await _dio.post('/api/auth/login', data: {'email': email, 'password': password});
    return AuthResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> getProfile() async {
    final res = await _dio.get('/api/auth/me');
    return User.fromJson((res.data as Map)['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _dio.put('/api/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword});
  }
}

final authService = AuthService();
