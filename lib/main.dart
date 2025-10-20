import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'features/splash/splash_screen.dart';
import 'core/notify/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification service (no permission request here)
  await NotificationService().init();

  // Preload theme synchronously before runApp to avoid first-tap glitch
  final prefs = await SharedPreferences.getInstance();
  final themeIndex = prefs.getInt('theme_mode') ?? 0;
  final initialMode = ThemeMode.values[themeIndex];
  
  runApp(ProviderScope(child: VyntraApp(initialMode: initialMode)));
}

// Removed first-launch battery request; handled on Home entry

class VyntraApp extends StatefulWidget {
  final ThemeMode initialMode;
  const VyntraApp({super.key, required this.initialMode});
  @override
  State<VyntraApp> createState() => _VyntraAppState();
}

class _VyntraAppState extends State<VyntraApp> {
  late ThemeMode _mode = widget.initialMode;

  void _setMode(ThemeMode mode) async {
    setState(() {
      _mode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vyntra',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFE0E0E0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: const Color(0xFF333333),
      ),
      themeMode: _mode,
      home: SplashScreen(
        onReady: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(onThemeChange: _setMode, currentMode: _mode),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
