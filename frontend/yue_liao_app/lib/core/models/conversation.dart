import 'message.dart';

class Conversation {
  final String oderId;
  final String username;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime lastMessageAt;

  Conversation({
    required this.oderId,
    required this.username,
    this.lastMessage,
    this.unreadCount = 0,
    required this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      oderId: json['user_id'] ?? '',
      username: json['username'] ?? '',
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': oderId,
      'username': username,
      if (lastMessage != null) 'last_message': lastMessage!.toJson(),
      'unread_count': unreadCount,
      'last_message_at': lastMessageAt.toIso8601String(),
    };
  }

  Conversation copyWith({
    String? userId,
    String? username,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastMessageAt,
  }) {
    return Conversation(
      oderId: userId ?? this.oderId,
      username: username ?? this.username,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          oderId == other.oderId;

  @override
  int get hashCode => oderId.hashCode;
}
