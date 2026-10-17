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
  Future<bool> didPopRoute() async {
    // While the App Lock overlay is showing, swallow the system back button so
    // it cannot pop routes hidden underneath the lock screen.
    final lock = Provider.of<LockService>(context, listen: false);
    return lock.shouldPromptLock();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zelon Messenger',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppTheme.lightTheme,
      darkTheme: WhatsAppTheme.darkTheme,
      themeMode: ThemeMode.system,
      // The app always boots through the splash screen; the lock is drawn as
      // an overlay above the navigator (see builder) so it also appears when
      // the app is re-locked after being backgrounded, not only on cold start.
      home: const SplashScreen(),
      builder: (context, child) {
        return Consumer<LockService>(
          builder: (context, lock, _) {
            final locked = lock.shouldPromptLock();
            return Stack(
              fit: StackFit.expand,
              children: [
                // Keep the navigator mounted (and its routes' state alive)
                // underneath the lock; just block touch & keyboard focus
                // (e.g. an open text field) while locked.
                ExcludeFocus(
                  excluding: locked,
                  child: IgnorePointer(
                    ignoring: locked,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                if (locked)
                  LockScreen(
                    // LockService flips its unlocked flag and notifies
                    // listeners, which removes this overlay automatically.
                    onUnlocked: () {},
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
