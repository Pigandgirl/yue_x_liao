import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'e2e_helper_simple.dart';

class SessionService {
  final ApiService _apiService;
  final E2EHelper _e2eHelper;
  final FlutterSecureStorage _storage;

  SessionService(this._apiService, this._e2eHelper) : _storage = const FlutterSecureStorage();

  Future<bool> initSession(String recipientUsername) async {
    if (_e2eHelper.hasSessionKey(recipientUsername)) {
      return true;
    }

    try {
      final response = await _apiService.initSession(
        recipientUsername: recipientUsername,
        ephemeralKey: _e2eHelper.publicKeyBase64,
      );

      final sessionId = response['session_id'] as String?;
      final recipientKey = response['recipient_key'] as String?;
      final initiatorKey = response['initiator_key'] as String?;

      if (sessionId != null && recipientKey != null) {
        await _storage.write(
          key: 'session_${recipientUsername}_id',
          value: sessionId,
        );

        await _e2eHelper.initiateSession(recipientUsername, recipientKey);

        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> completeSession(String recipientUsername, String sessionId) async {
    try {
      await _apiService.completeSession(
        sessionId: sessionId,
        responseKey: _e2eHelper.publicKeyBase64,
      );

      await _storage.write(
        key: 'session_${recipientUsername}_completed',
        value: 'true',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> checkSession(String recipientUsername) async {
    try {
      return await _apiService.checkSession(recipientUsername);
    } catch (e) {
      return null;
    }
  }

  bool hasEstablishedSession(String recipientUsername) {
    return _e2eHelper.hasSessionKey(recipientUsername);
  }

  Future<String?> getSessionId(String recipientUsername) async {
    return await _storage.read(key: 'session_${recipientUsername}_id');
  }
}
