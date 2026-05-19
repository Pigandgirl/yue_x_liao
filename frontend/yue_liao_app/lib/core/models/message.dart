class Message {
  final String id;
  final String senderId;
  final String? senderUsername;
  final String receiverId;
  final String? receiverUsername;
  final String encryptedPayload;
  final Map<String, dynamic>? payload;
  final bool isRead;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.senderId,
    this.senderUsername,
    required this.receiverId,
    this.receiverUsername,
    required this.encryptedPayload,
    this.payload,
    this.isRead = false,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? payload;
    if (json['payload'] != null) {
      payload = json['payload'] as Map<String, dynamic>;
    } else if (json['encrypted_payload'] != null) {
      try {
        payload = json['encrypted_payload'] as Map<String, dynamic>;
      } catch (_) {
        payload = {'text': json['encrypted_payload']};
      }
    }

    return Message(
      id: json['id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderUsername: json['sender_username'],
      receiverId: json['receiver_id'] ?? '',
      receiverUsername: json['receiver_username'],
      encryptedPayload: json['encrypted_payload'] ?? '',
      payload: payload,
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      if (senderUsername != null) 'sender_username': senderUsername,
      'receiver_id': receiverId,
      if (receiverUsername != null) 'receiver_username': receiverUsername,
      'encrypted_payload': encryptedPayload,
      if (payload != null) 'payload': payload,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get text {
    if (payload != null && payload!['text'] != null) {
      return payload!['text'].toString();
    }
    return encryptedPayload;
  }

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
