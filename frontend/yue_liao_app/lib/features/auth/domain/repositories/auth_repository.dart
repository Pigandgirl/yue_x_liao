import '../models/user.dart';

abstract class AuthRepository {
  Future<User> register({
    required String username,
    required String email,
    required String password,
  });

  Future<String> login({
    required String email,
    required String password,
  });

  Future<void> logout();

  Future<User?> getCurrentUser();

  Future<bool> isAuthenticated();

  Future<String?> getToken();

  Future<void> saveToken(String token);

  Future<void> deleteToken();
}
