class User {
  final int id;
  final String email;
  const User({required this.id, required this.email});
  factory User.fromJson(Map<String, dynamic> j) =>
      User(id: (j['id'] as num).toInt(), email: (j['email'] ?? '') as String);
  Map<String, dynamic> toJson() => {'id': id, 'email': email};
}

class AuthResponse {
  final bool success;
  final String token;
  final User user;
  const AuthResponse({required this.success, required this.token, required this.user});
  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
        success: j['success'] == true,
        token: (j['token'] ?? '') as String,
        user: User.fromJson(j['user'] as Map<String, dynamic>),
      );
}
