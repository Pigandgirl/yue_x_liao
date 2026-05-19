import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WebSocketMessage({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<WebSocketConnectionState> _stateController =
      StreamController<WebSocketConnectionState>.broadcast();

  Timer? _reconnectTimer;
  String? _currentUrl;
  String? _authToken;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;
  WebSocketConnectionState get state =>
      _stateController.hasListener ? WebSocketConnectionState.disconnected : WebSocketConnectionState.disconnected;

  void connect(String url, {String? authToken}) {
    _currentUrl = url;
    _authToken = authToken;
    _reconnectAttempts = 0;
    _establishConnection();
  }

  void _establishConnection() {
    if (_currentUrl == null) return;

    _stateController.add(WebSocketConnectionState.connecting);

    try {
      final headers = <String, dynamic>{};
      if (_authToken != null) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      _channel = WebSocketChannel.connect(
        Uri.parse(_currentUrl!),
        protocols: headers,
      );

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _stateController.add(WebSocketConnectionState.connected);
      _reconnectAttempts = 0;
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
      // Handle parse error
    }
  }

  void _onError(Object error) {
    _handleConnectionError(error);
  }

  void _onDone() {
    if (_stateController.hasListener) {
      _stateController.add(WebSocketConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _handleConnectionError(Object error) {
    _stateController.add(WebSocketConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    _stateController.add(WebSocketConnectionState.reconnecting);

    final delay = Duration(milliseconds: 1000 * _reconnectAttempts);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _establishConnection);
  }

  void send(WebSocketMessage message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message.toJson()));
    }
  }

  void sendRaw(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _stateController.add(WebSocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
