import '../models/message.dart';

abstract class ChatRepository {
  Stream<Message> get messageStream;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendMessage(Message message);
  Future<List<Conversation>> getConversations();
  Future<List<Message>> getMessages(String conversationId);
  Future<Conversation> createConversation(List<String> participantIds);
}
