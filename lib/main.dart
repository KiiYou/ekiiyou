import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/database_helper.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'state/vocabulary_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.ensureInitialized();
  await NotificationService.instance.initialize();

  final controller = VocabularyController();
  await controller.initialize();

  runApp(
    SmartVocabularyApp(
      controller: controller,
      showSplashOnLaunch: true,
    ),
  );
}

class SmartVocabularyApp extends StatelessWidget {
  final VocabularyController controller;
  final bool showSplashOnLaunch;

  const SmartVocabularyApp({
    super.key,
    required this.controller,
    this.showSplashOnLaunch = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return MaterialApp(
          title: controller.strings.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.themeMode,
          locale: Locale(settings.languageCode),
          supportedLocales: const [
            Locale('ar'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: showSplashOnLaunch
              ? SplashScreen(controller: controller)
              : MainNavigationScreen(controller: controller),
        );
      },
    );
  }
}
