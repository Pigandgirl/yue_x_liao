import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiService {
  final AppConfig _config;
  final FlutterSecureStorage _storage;
  static const String _tokenKey = 'auth_token';

  ApiService(this._config) : _storage = const FlutterSecureStorage();

  String get _baseUrl => _config.apiBaseUrl;

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Map<String, String> _headers({bool withAuth = false, String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (withAuth) {
      final authToken = token ?? _config.apiBaseUrl;
      headers['Authorization'] = 'Bearer $authToken';
    }

    return headers;
  }

  Future<dynamic> _handleResponse(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Request failed';
      try {
        final body = jsonDecode(response.body);
        message = body['error'] ?? body['message'] ?? message;
      } catch (_) {}
      throw ApiException(message, response.statusCode);
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? publicKey,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        if (publicKey != null) 'public_key': publicKey,
      }),
    );

    final data = await _handleResponse(response);
    if (data['token'] != null) {
      await saveToken(data['token']);
    }
    return data;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final data = await _handleResponse(response);
    if (data['token'] != null) {
      await saveToken(data['token']);
    }
    return data;
  }

  Future<Map<String, dynamic>> getCurrentUser({String? token}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/me'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    return await _handleResponse(response);
  }

  Future<void> updatePublicKey(String publicKey, {String? token}) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/public-key'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
      body: jsonEncode({'public_key': publicKey}),
    );

    await _handleResponse(response);
  }

  Future<List<dynamic>> searchUsers(String query, {String? token}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/users/search?q=${Uri.encodeComponent(query)}'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    final data = await _handleResponse(response);
    return data['users'] ?? [];
  }

  Future<List<dynamic>> getConversations({String? token}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/conversations'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    final data = await _handleResponse(response);
    return data['conversations'] ?? [];
  }

  Future<List<dynamic>> getMessages({
    required String withUsername,
    int limit = 50,
    String? after,
    String? token,
  }) async {
    var url = '$_baseUrl/messages?with=${Uri.encodeComponent(withUsername)}&limit=$limit';
    if (after != null) {
      url += '&after=${Uri.encodeComponent(after)}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    final data = await _handleResponse(response);
    return data['messages'] ?? [];
  }

  Future<int> getUnreadCount({String? token}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/messages/unread'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    final data = await _handleResponse(response);
    return data['total_unread'] ?? 0;
  }

  Future<void> markAsRead(String messageId, {String? token}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/messages/read'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
      body: jsonEncode({'message_id': messageId}),
    );

    await _handleResponse(response);
  }

  Future<void> markConversationAsRead(String username, {String? token}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/conversations/${Uri.encodeComponent(username)}/read'),
      headers: _headers(withAuth: true, token: token ?? await getToken()),
    );

    await _handleResponse(response);
  }

  Future<bool> isUserOnline(String username) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/users/${Uri.encodeComponent(username)}/online'),
    );

    try {
      final data = await _handleResponse(response);
      return data['is_online'] ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    await deleteToken();
  }
}
