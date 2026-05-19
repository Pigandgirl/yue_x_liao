import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/chat_websocket_service.dart';
import '../services/e2e_helper_simple.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService;
  final ChatWebSocketService _wsService;
  final E2EHelper _e2eHelper;

  List<Conversation> _conversations = [];
  Map<String, List<Message>> _messagesByConversation = {};
  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  String? _error;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _encryptedMessageSubscription;

  List<Conversation> get conversations => _conversations;
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  String? get error => _error;

  ChatProvider(this._apiService, this._wsService, this._e2eHelper) {
    _initWebSocket();
  }

  void _initWebSocket() {
    _messageSubscription = _wsService.messageStream.listen(_onWebSocketMessage);
    _stateSubscription = _wsService.stateStream.listen((state) {
      if (state == ConnectionState.connected) {
        loadConversations();
      }
      notifyListeners();
    });

    _encryptedMessageSubscription = _wsService.encryptedMessageStream.listen((data) async {
      final from = data['from'] as String?;
      final payload = data['payload'] as Map<String, dynamic>?;
      final message = data['message'] as Message?;

      if (from != null && _e2eHelper.hasSessionKey(from)) {
        try {
          final encryptedPayload = EncryptedPayload.fromJson(payload!);
          final decryptedText = _e2eHelper.decrypt(encryptedPayload, from);
          final decryptedPayload = {'text': decryptedText};

          if (message != null) {
            final decryptedMessage = message.copyWith(
              payload: decryptedPayload,
              encryptedPayload: decryptedText,
            );
            _addMessageToConversation(from, decryptedMessage);
          }
        } catch (e) {
          _error = 'Failed to decrypt message: $e';
          notifyListeners();
        }
      } else {
        if (message != null) {
          _addMessageToConversation(from!, message);
        }
      }
    });
  }

  void _onWebSocketMessage(WebSocketMessage message) {
    switch (message.type) {
      case 'chat':
      case 'offline_message':
      case 'message_sent':
        if (message.message != null && message.from != null) {
          if (_e2eHelper.hasSessionKey(message.from!)) {
            if (message.payload != null && message.payload!['ciphertext'] != null) {
              try {
                final encryptedPayload = EncryptedPayload.fromJson(message.payload!);
                final decryptedText = _e2eHelper.decrypt(encryptedPayload, message.from!);
                final decryptedMessage = message.message!.copyWith(
                  payload: {'text': decryptedText},
                  encryptedPayload: decryptedText,
                );
                _addMessageToConversation(message.from!, decryptedMessage);
              } catch (e) {
                _addMessageToConversation(message.from!, message.message!);
              }
            } else {
              _addMessageToConversation(message.from!, message.message!);
            }
          } else {
            _addMessageToConversation(message.from!, message.message!);
          }
        }
        break;
      case 'session_init':
        _handleSessionInit(message);
        break;
      case 'session_complete':
        _handleSessionComplete(message);
        break;
      case 'typing':
        break;
      case 'pong':
        break;
      case 'error':
        _error = message.error;
        notifyListeners();
        break;
    }
  }

  void _handleSessionInit(WebSocketMessage message) async {
    if (message.from != null && message.ephemeralKey != null) {
      try {
        await _e2eHelper.initiateSession(message.from!, message.ephemeralKey!);
        _wsService.sendSessionComplete(message.sessionId ?? '');
      } catch (e) {
        _error = 'Failed to establish session: $e';
        notifyListeners();
      }
    }
  }

  void _handleSessionComplete(WebSocketMessage message) async {
    if (message.to != null && message.ephemeralKey != null) {
      try {
        await _e2eHelper.initiateSession(message.to!, message.ephemeralKey!);
      } catch (e) {
        _error = 'Failed to complete session: $e';
        notifyListeners();
      }
    }
  }

  void _addMessageToConversation(String username, Message message) {
    if (!_messagesByConversation.containsKey(username)) {
      _messagesByConversation[username] = [];
    }

    final messages = _messagesByConversation[username]!;
    if (!messages.any((m) => m.id == message.id)) {
      messages.add(message);
      _sortMessages(username);

      final convIndex = _conversations.indexWhere((c) => c.username == username);
      if (convIndex >= 0) {
        _conversations[convIndex] = _conversations[convIndex].copyWith(
          lastMessage: message,
          lastMessageAt: message.createdAt,
        );
        _sortConversations();
      }
    }

    notifyListeners();
  }

  void _sortMessages(String username) {
    if (_messagesByConversation.containsKey(username)) {
      _messagesByConversation[username]!.sort(
        (a, b) => a.createdAt.compareTo(b.createdAt),
      );
    }
  }

  void _sortConversations() {
    _conversations.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }

  List<Message> getMessages(String username) {
    return _messagesByConversation[username] ?? [];
  }

  Future<void> connect(String token) async {
    await _wsService.connect(token);
  }

  Future<void> disconnect() async {
    await _wsService.disconnect();
  }

  Future<void> loadConversations() async {
    _isLoadingConversations = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _apiService.getConversations();
      _conversations = data.map((c) => Conversation.fromJson(c)).toList();
      _sortConversations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String username, {bool refresh = false}) async {
    if (!refresh && _messagesByConversation.containsKey(username)) {
      return;
    }

    _isLoadingMessages = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _apiService.getMessages(withUsername: username);
      _messagesByConversation[username] = data.map((m) => Message.fromJson(m)).toList();
      _sortMessages(username);

      await _apiService.markConversationAsRead(username);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> initSession(String recipientUsername) async {
    try {
      final response = await _apiService.initSession(
        recipientUsername: recipientUsername,
        ephemeralKey: _e2eHelper.publicKeyBase64,
      );

      final sessionId = response['session_id'] as String?;
      final recipientKey = response['recipient_key'] as String?;

      if (sessionId != null && recipientKey != null) {
        await _e2eHelper.initiateSession(recipientUsername, recipientKey);
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void sendMessage(String to, String text) {
    if (!_e2eHelper.hasSessionKey(to)) {
      initSession(to);
    }

    _wsService.sendChatMessage(to: to, text: text);
  }

  void sendEncryptedMessage(String to, String text) {
    if (_e2eHelper.hasSessionKey(to)) {
      _wsService.sendEncryptedMessage(to: to, text: text);
    } else {
      _error = 'No encryption session established with $to';
      notifyListeners();
    }
  }

  void sendTyping(String to, {bool typing = true}) {
    _wsService.sendTyping(to, typing: typing);
  }

  void markAsRead(String username, Message message) {
    _wsService.sendReadReceipt(message);
    _apiService.markAsRead(message.id);
  }

  Future<void> refreshMessages(String username) async {
    await loadMessages(username, refresh: true);
  }

  bool get isConnected => _wsService.isConnected;

  bool hasSessionKey(String username) => _e2eHelper.hasSessionKey(username);

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _stateSubscription?.cancel();
    _encryptedMessageSubscription?.cancel();
    _wsService.dispose();
    super.dispose();
  }
}

extension MessageExtension on Message {
  Message copyWith({
    String? id,
    String? senderId,
    String? senderUsername,
    String? receiverId,
    String? receiverUsername,
    String? encryptedPayload,
    Map<String, dynamic>? payload,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      receiverId: receiverId ?? this.receiverId,
      receiverUsername: receiverUsername ?? this.receiverUsername,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      payload: payload ?? this.payload,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
