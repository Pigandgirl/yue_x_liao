import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../models/message.dart';

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

  WebSocketMessage({
    required this.type,
    this.from,
    this.to,
    this.payload,
    this.message,
    this.error,
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
    };
  }
}

class ChatWebSocketService {
  final AppConfig _config;
  WebSocketChannel? _channel;
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();

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

  ChatWebSocketService(this._config);

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
      _messageController.add(wsMessage);
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
    final message = WebSocketMessage(
      type: 'chat',
      to: to,
      payload: {'text': text},
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
  }

  bool get isConnected => _state == ConnectionState.connected;
}
