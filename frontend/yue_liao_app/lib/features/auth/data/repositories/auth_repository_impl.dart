import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/services/encryption_service.dart';
import '../domain/models/user.dart';
import '../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AppConfig _config;
  final EncryptionService _encryptionService;
  final FlutterSecureStorage _secureStorage;

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'current_user';

  AuthRepositoryImpl(this._config, this._encryptionService)
      : _secureStorage = const FlutterSecureStorage();

  @override
  Future<User> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final hashedPassword = _encryptionService.hashPassword(password);

    final response = await http.post(
      Uri.parse('${_config.apiBaseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': hashedPassword,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return User.fromJson(data['user'] as Map<String, dynamic>);
    } else {
      throw Exception('Registration failed: ${response.body}');
    }
  }

  @override
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final hashedPassword = _encryptionService.hashPassword(password);

    final response = await http.post(
      Uri.parse('${_config.apiBaseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': hashedPassword,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String;
      await saveToken(token);

      if (data['user'] != null) {
        await _saveUser(User.fromJson(data['user'] as Map<String, dynamic>));
      }

      return token;
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  @override
  Future<void> logout() async {
    await deleteToken();
    await _secureStorage.delete(key: _userKey);
  }

  @override
  Future<User?> getCurrentUser() async {
    final userJson = await _secureStorage.read(key: _userKey);
    if (userJson != null) {
      return User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    }
    return null;
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  @override
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  @override
  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<void> _saveUser(User user) async {
    await _secureStorage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }
}
