import 'dart:async';
import '../../../core/services/websocket_service.dart';
import '../domain/models/message.dart';
import '../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final WebSocketService _webSocketService;
  StreamController<Message>? _messageController;
  StreamSubscription? _messageSubscription;

  ChatRepositoryImpl(this._webSocketService);

  @override
  Stream<Message> get messageStream {
    _messageController ??= StreamController<Message>.broadcast();
    return _messageController!.stream;
  }

  @override
  Future<void> connect() async {
    await _webSocketService.connect('ws://localhost:8080/ws');
    _messageSubscription = _webSocketService.messageStream.listen((message) {
      if (message.type == 'chat_message') {
        final chatMessage = Message.fromJson(message.data);
        _messageController?.add(chatMessage);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _messageSubscription?.cancel();
    _messageController?.close();
    _messageController = null;
    _webSocketService.disconnect();
  }

  @override
  Future<void> sendMessage(Message message) async {
    _webSocketService.send(WebSocketMessage(
      type: 'chat_message',
      data: message.toJson(),
    ));
  }

  @override
  Future<List<Conversation>> getConversations() async {
    return [];
  }

  @override
  Future<List<Message>> getMessages(String conversationId) async {
    return [];
  }

  @override
  Future<Conversation> createConversation(List<String> participantIds) async {
    return Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      participantIds: participantIds,
      createdAt: DateTime.now(),
    );
  }
}
