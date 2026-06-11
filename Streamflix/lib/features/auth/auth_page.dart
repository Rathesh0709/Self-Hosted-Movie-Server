import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/watch_history_provider.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  bool _isLogin = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_isLogin) {
        await notifier.login(_email.text.trim(), _password.text);
      } else {
        await notifier.register(_email.text.trim(), _password.text);
      }
      ref.read(watchHistoryProvider.notifier).syncWithServer();
      ref.read(favoritesProvider.notifier).fetchFavorites();
      if (mounted) context.go('/home');
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?['error']?.toString() ?? 'Authentication failed');
    } catch (_) {
      setState(() => _error = 'Authentication failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.navyCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_isLogin ? 'Welcome back' : 'Create account',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Sync favorites & watch history across devices.',
                      style: TextStyle(color: AppColors.mutedForeground, fontSize: 13)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _segment('Login', _isLogin, () => setState(() => _isLogin = true)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child:
                            _segment('Register', !_isLogin, () => setState(() => _isLogin = false)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.destructive, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? 'Login' : 'Create account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.mutedForeground)),
        ),
      );
}
