import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/lock_service.dart';
import 'services/chat_design_service.dart';
import 'screens/splash_screen.dart';
import 'screens/lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  final lockService = LockService();
  final chatDesignService = ChatDesignService();
  await lockService.init();
  await chatDesignService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(api: apiService),
        ),
        ChangeNotifierProvider<LockService>.value(value: lockService),
        ChangeNotifierProvider<ChatDesignService>.value(value: chatDesignService),
      ],
      child: const ZelonMessengerApp(),
    ),
  );
}

class ZelonMessengerApp extends StatefulWidget {
  const ZelonMessengerApp({super.key});

  @override
  State<ZelonMessengerApp> createState() => _ZelonMessengerAppState();
}

class _ZelonMessengerAppState extends State<ZelonMessengerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = Provider.of<LockService>(context, listen: false);
    if (state == AppLifecycleState.paused) {
      lock.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      lock.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = Provider.of<LockService>(context);

    return MaterialApp(
      title: 'Zelon Messenger',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppTheme.lightTheme,
      darkTheme: WhatsAppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: lock.shouldPromptLock()
          ? LockScreen(
              onUnlocked: () {
                setState(() {});
              },
            )
          : const SplashScreen(),
    );
  }
}
