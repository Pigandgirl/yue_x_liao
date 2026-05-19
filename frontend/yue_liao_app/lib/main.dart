import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/services/api_service.dart';
import 'core/services/chat_websocket_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/chat_provider.dart';
import 'features/auth/presentation/screens/splash_screen.dart';

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
        Provider<ApiService>(
          create: (ctx) => ApiService(ctx.read<AppConfig>()),
          dispose: (_, __) {},
        ),
        Provider<ChatWebSocketService>(
          create: (ctx) => ChatWebSocketService(ctx.read<AppConfig>()),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (ctx) => AuthProvider(ctx.read<ApiService>()),
        ),
        ChangeNotifierProxyProvider<ApiService, ChatProvider>(
          create: (ctx) => ChatProvider(
            ctx.read<ApiService>(),
            ctx.read<ChatWebSocketService>(),
          ),
          update: (_, __, previous) =>
              previous ?? ChatProvider(
                ctx.read<ApiService>(),
                ctx.read<ChatWebSocketService>(),
              ),
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
