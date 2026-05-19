import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/chat_websocket_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService;
  final ChatWebSocketService _wsService;

  List<Conversation> _conversations = [];
  Map<String, List<Message>> _messagesByConversation = {};
  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  String? _error;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _stateSubscription;

  List<Conversation> get conversations => _conversations;
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  String? get error => _error;

  ChatProvider(this._apiService, this._wsService) {
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
  }

  void _onWebSocketMessage(WebSocketMessage message) {
    switch (message.type) {
      case 'chat':
      case 'offline_message':
      case 'message_sent':
        if (message.message != null && message.from != null) {
          _addMessageToConversation(message.from!, message.message!);
        }
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
      _messagesByConversation[username] =
          data.map((m) => Message.fromJson(m)).toList();
      _sortMessages(username);

      await _apiService.markConversationAsRead(username);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  void sendMessage(String to, String text) {
    _wsService.sendChatMessage(to: to, text: text);
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

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _stateSubscription?.cancel();
    _wsService.dispose();
    super.dispose();
  }
}
