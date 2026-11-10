import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  NotificationService._internal();

  static const int _dailyReminderId = 1001;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open Smart Vocabulary Notebook',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _plugin.initialize(initSettings);
      _initialized = true;
    } catch (_) {
      // Gracefully ignore initialization errors on unsupported desktop/test environments
    }
  }

  /// Requests notification permissions on Android 13+ and iOS/macOS.
  /// Returns true if granted (or if running on a platform that does not require runtime permission).
  Future<bool> requestPermissions() async {
    await initialize();
    try {
      if (kIsWeb) return false;
      if (Platform.isAndroid) {
        final androidImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImplementation != null) {
          final granted = await androidImplementation
              .requestNotificationsPermission();
          return granted ?? true;
        }
        return true;
      } else if (Platform.isIOS) {
        final iosImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (iosImplementation != null) {
          final granted = await iosImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        }
      } else if (Platform.isMacOS) {
        final macImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        if (macImplementation != null) {
          final granted = await macImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await initialize();
    final granted = await requestPermissions();
    if (!granted) {
      return false;
    }

    try {
      await _plugin.cancel(_dailyReminderId);

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const androidDetails = AndroidNotificationDetails(
        'daily_vocab_review_channel',
        'Daily Vocabulary Review',
        channelDescription: 'Daily reminder to review saved English words',
        importance: Importance.high,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _plugin.zonedSchedule(
        _dailyReminderId,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      // On desktop platforms where zonedSchedule may not be supported, return true
      // so the user's reminder preference is still saved without crashing.
      return true;
    }
  }

  Future<void> cancelDailyReminder() async {
    await initialize();
    try {
      await _plugin.cancel(_dailyReminderId);
    } catch (_) {}
  }
}
