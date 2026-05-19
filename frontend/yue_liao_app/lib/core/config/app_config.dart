class AppConfig {
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String minioEndpoint;
  final String minioBucket;
  final bool enableEncryption;
  final int connectionTimeout;
  final int wsReconnectDelay;

  const AppConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.minioEndpoint,
    required this.minioBucket,
    this.enableEncryption = true,
    this.connectionTimeout = 30000,
    this.wsReconnectDelay = 5000,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
      minioEndpoint: 'http://localhost:9000',
      minioBucket: 'user-files',
      enableEncryption: true,
      connectionTimeout: 30000,
      wsReconnectDelay: 5000,
    );
  }

  factory AppConfig.production() {
    return const AppConfig(
      apiBaseUrl: 'https://api.yueliao.app/api/v1',
      wsBaseUrl: 'wss://api.yueliao.app/ws',
      minioEndpoint: 'https://minio.yueliao.app',
      minioBucket: 'user-files',
      enableEncryption: true,
      connectionTimeout: 30000,
      wsReconnectDelay: 5000,
    );
  }
}
