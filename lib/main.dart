import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'features/splash/splash_screen.dart';
// NotificationService is initialized later from Home; no import needed here

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Start app immediately for zero-delay splash; load preferences after
  runApp(const ProviderScope(child: VyntraApp(initialMode: ThemeMode.system)));
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

  @override
  void initState() {
    super.initState();
    // Load theme and lightweight services after first frame to avoid startup delay
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt('theme_mode');
      if (themeIndex != null) {
        setState(() {
          _mode = ThemeMode.values[themeIndex];
        });
      }
    });
  }

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
        next: HomeScreen(onThemeChange: _setMode),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
