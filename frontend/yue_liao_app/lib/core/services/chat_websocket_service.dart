import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../models/message.dart';
import 'e2e_helper_simple.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebSocketMessage {
  final String type;
  final String? from;
  final String? to;
  final Map<String, dynamic>? payload;
  final Message? message;
  final String? error;
  final String? sessionId;
  final String? ephemeralKey;
  final String? recipientKey;

  WebSocketMessage({
    required this.type,
    this.from,
    this.to,
    this.payload,
    this.message,
    this.error,
    this.sessionId,
    this.ephemeralKey,
    this.recipientKey,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] ?? '',
      from: json['from'],
      to: json['to'],
      payload: json['payload'] as Map<String, dynamic>?,
      message: json['message'] != null
          ? Message.fromJson(json['message'])
          : null,
      error: json['error'],
      sessionId: json['session_id'],
      ephemeralKey: json['ephemeral_key'],
      recipientKey: json['recipient_key'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (payload != null) 'payload': payload,
      if (message != null) 'message': message!.toJson(),
      if (error != null) 'error': error,
      if (sessionId != null) 'session_id': sessionId,
      if (ephemeralKey != null) 'ephemeral_key': ephemeralKey,
      if (recipientKey != null) 'recipient_key': recipientKey,
    };
  }
}

class ChatWebSocketService {
  final AppConfig _config;
  final E2EHelper _e2eHelper;
  WebSocketChannel? _channel;
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<Map<String, dynamic>> _encryptedMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  String? _token;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 10;
  static const Duration reconnectDelay = Duration(seconds: 2);

  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  Stream<ConnectionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get encryptedMessageStream => _encryptedMessageController.stream;

  ChatWebSocketService(this._config, this._e2eHelper);

  Future<void> connect(String token) async {
    _token = token;
    _reconnectAttempts = 0;
    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (_token == null) return;

    _updateState(ConnectionState.connecting);

    try {
      final wsUrl = _config.wsBaseUrl.replaceFirst('http', 'ws');
      final uri = Uri.parse('$wsUrl?token=$_token');

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _updateState(ConnectionState.connected);
      _reconnectAttempts = 0;
      _startPingTimer();
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final wsMessage = WebSocketMessage.fromJson(data);

      if (wsMessage.type == 'chat' && wsMessage.from != null && wsMessage.payload != null) {
        final senderUsername = wsMessage.from!;
        if (_e2eHelper.hasSessionKey(senderUsername)) {
          try {
            final encryptedPayload = EncryptedPayload.fromJson(wsMessage.payload!);
            final decryptedText = _e2eHelper.decrypt(encryptedPayload, senderUsername);
            final decryptedPayload = {'text': decryptedText};
            final decryptedMessage = WebSocketMessage(
              type: wsMessage.type,
              from: wsMessage.from,
              to: wsMessage.to,
              payload: decryptedPayload,
              message: wsMessage.message,
            );
            _messageController.add(decryptedMessage);
          } catch (e) {
            _messageController.add(wsMessage);
          }
        } else {
          _encryptedMessageController.add({
            'from': wsMessage.from,
            'payload': wsMessage.payload,
            'message': wsMessage.message,
          });
        }
      } else {
        _messageController.add(wsMessage);
      }
    } catch (e) {
    }
  }

  void _onError(Object error) {
    _handleConnectionError(error);
  }

  void _onDone() {
    _updateState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _handleConnectionError(Object error) {
    _updateState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    _updateState(ConnectionState.reconnecting);

    final delay = Duration(
      milliseconds: reconnectDelay.inMilliseconds * _reconnectAttempts,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _establishConnection();
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      sendPing();
    });
  }

  void _updateState(ConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void send(WebSocketMessage message) {
    if (_channel != null && _state == ConnectionState.connected) {
      _channel!.sink.add(jsonEncode(message.toJson()));
    }
  }

  void sendChatMessage({
    required String to,
    required String text,
  }) {
    Map<String, dynamic> payload;

    if (_e2eHelper.hasSessionKey(to)) {
      final encrypted = _e2eHelper.encrypt(text, to);
      payload = encrypted.toJson();
    } else {
      payload = {'text': text};
    }

    final message = WebSocketMessage(
      type: 'chat',
      to: to,
      payload: payload,
    );
    send(message);
  }

  void sendEncryptedMessage({
    required String to,
    required String text,
  }) {
    final encrypted = _e2eHelper.encrypt(text, to);
    final payload = encrypted.toJson();

    final message = WebSocketMessage(
      type: 'chat',
      to: to,
      payload: payload,
    );
    send(message);
  }

  void sendSessionInit(String recipientUsername) {
    final message = WebSocketMessage(
      type: 'session_init',
      to: recipientUsername,
      ephemeralKey: _e2eHelper.publicKeyBase64,
    );
    send(message);
  }

  void sendSessionComplete(String sessionId) {
    final message = WebSocketMessage(
      type: 'session_complete',
      sessionId: sessionId,
      ephemeralKey: _e2eHelper.publicKeyBase64,
    );
    send(message);
  }

  void sendTyping(String to, {bool typing = true}) {
    final message = WebSocketMessage(
      type: 'typing',
      to: to,
      payload: {'typing': typing},
    );
    send(message);
  }

  void sendReadReceipt(Message message) {
    final wsMessage = WebSocketMessage(
      type: 'read',
      message: message,
    );
    send(wsMessage);
  }

  void sendPing() {
    send(WebSocketMessage(type: 'ping'));
  }

  Future<void> reconnect() async {
    await disconnect();
    await _establishConnection();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    _updateState(ConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _stateController.close();
    await _encryptedMessageController.close();
  }

  bool get isConnected => _state == ConnectionState.connected;

  String get publicKeyBase64 => _e2eHelper.publicKeyBase64;

  bool hasSessionKey(String username) => _e2eHelper.hasSessionKey(username);

  Future<void> initiateSession(String username, String recipientKey) async {
    await _e2eHelper.initiateSession(username, recipientKey);
  }
}
