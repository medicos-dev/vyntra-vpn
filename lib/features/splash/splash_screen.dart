import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onReady;
  const SplashScreen({super.key, required this.onReady});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideInFromLeft;
  late final Animation<double> _impactScale;
  late final Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _slideInFromLeft = Tween<Offset>(
      begin: const Offset(-1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _impactScale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.7, curve: Curves.easeOutBack)),
    );

    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1.0, curve: Curves.easeOut)),
    );

    // Start animation sequence
    _controller.forward();

    // Preload any required lightweight data here if needed
    _preload();
  }

  Future<void> _preload() async {
    // Simulate brief load while animation runs
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    widget.onReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: FadeTransition(
              opacity: _fadeOut,
              child: ScaleTransition(
                scale: _impactScale,
                child: SlideTransition(
                  position: _slideInFromLeft,
                  child: Image.asset(
                    'assets/no bg.png',
                    width: 120,
                    height: 120,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


