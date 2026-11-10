import 'dart:async';
import 'package:flutter/material.dart';
import '../state/vocabulary_controller.dart';
import 'main_navigation_screen.dart';

class SplashScreen extends StatefulWidget {
  final VocabularyController controller;
  final Duration minimumSplashDuration;

  const SplashScreen({
    super.key,
    required this.controller,
    this.minimumSplashDuration = const Duration(milliseconds: 900),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepareApp();
  }

  Future<void> _prepareApp() async {
    await Future.wait([
      widget.controller.initialize(),
      Future<void>.delayed(widget.minimumSplashDuration),
    ]);
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MainNavigationScreen(controller: widget.controller);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.88, end: 1.0),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.controller.strings.appTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
