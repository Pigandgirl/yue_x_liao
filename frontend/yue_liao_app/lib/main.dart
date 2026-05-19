import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/chat/data/repositories/chat_repository_impl.dart';
import 'features/chat/domain/repositories/chat_repository.dart';
import 'features/file/data/repositories/file_repository_impl.dart';
import 'features/file/domain/repositories/file_repository.dart';
import 'core/services/websocket_service.dart';
import 'core/services/encryption_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YueLiaoApp());
}

class YueLiaoApp extends StatelessWidget {
  const YueLiaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>(
          create: (_) => AppConfig.fromEnvironment(),
          dispose: (_, __) {},
        ),
        Provider<EncryptionService>(
          create: (_) => EncryptionService(),
          dispose: (_, __) {},
        ),
        Provider<WebSocketService>(
          create: (_) => WebSocketService(),
          dispose: (_, service) => service.disconnect(),
        ),
        ProxyProvider<WebSocketService, ChatRepository>(
          update: (_, wsService, __) => ChatRepositoryImpl(wsService),
        ),
        ProxyProvider2<AppConfig, EncryptionService, FileRepository>(
          update: (_, config, encryption, __) =>
              FileRepositoryImpl(config, encryption),
        ),
        ProxyProvider2<AppConfig, EncryptionService, AuthRepository>(
          update: (_, config, encryption, __) =>
              AuthRepositoryImpl(config, encryption),
        ),
      ],
      child: MaterialApp(
        title: 'Yue Liao',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
      ),
    );
  }
}
