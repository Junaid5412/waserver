import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(api: apiService),
        ),
      ],
      child: const ZelonMessengerApp(),
    ),
  );
}

class ZelonMessengerApp extends StatelessWidget {
  const ZelonMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zelon Messenger',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppTheme.lightTheme,
      darkTheme: WhatsAppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
