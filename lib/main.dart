import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'core/notify/notification_service.dart';
import 'core/services/battery_optimization_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification service early in app lifecycle
  await NotificationService().init();
  
  // Check if this is first launch and request battery optimization
  await _checkFirstLaunch();
  
  runApp(const ProviderScope(child: VyntraApp()));
}

Future<void> _checkFirstLaunch() async {
  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;
  
  if (isFirstLaunch) {
    // Request battery optimization exemption on first launch
    await BatteryOptimizationService.requestBatteryOptimizationExemption();
    await prefs.setBool('is_first_launch', false);
  }
}

class VyntraApp extends StatefulWidget {
  const VyntraApp({super.key});
  @override
  State<VyntraApp> createState() => _VyntraAppState();
}

class _VyntraAppState extends State<VyntraApp> {
  ThemeMode _mode = ThemeMode.system;
  
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    setState(() {
      _mode = ThemeMode.values[themeIndex];
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
      home: HomeScreen(
        onThemeChange: _setMode, 
        currentMode: _mode,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
