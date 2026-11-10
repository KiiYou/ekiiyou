import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Honest outcome of trying to schedule the daily reminder.
enum ReminderScheduleResult {
  scheduled,
  permissionDenied,

  /// The platform has no local-notification support (e.g. Windows desktop in
  /// this plugin version) or the OS rejected the request.
  failed,
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  NotificationService._internal();

  static const int _dailyReminderId = 1001;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux);

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;
    try {
      tz.initializeTimeZones();
      await _configureLocalTimezone();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open EKiiYou',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _plugin.initialize(initSettings);
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.initialize failed: $e');
    }
  }

  /// Without this, `tz.local` stays UTC and an 8:00 PM reminder would fire at
  /// 8:00 PM UTC (e.g. 10:00 PM in Egypt).
  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Unknown identifier or plugin unavailable: fall back to a fixed-offset
      // zone matching the device's current UTC offset so the time is still
      // correct (it just won't follow future DST changes).
      debugPrint('Could not resolve device timezone, using offset: $e');
      final offset = DateTime.now().timeZoneOffset;
      tz.setLocalLocation(
        tz.Location('Device', [], [], [
          tz.TimeZone(
            offset.inMilliseconds,
            isDst: false,
            abbreviation: 'LOCAL',
          ),
        ]),
      );
    }
  }

  /// Returns whether notifications are currently allowed. When [request] is
  /// true, the OS permission prompt may be shown.
  Future<bool> _hasPermission({required bool request}) async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return false;
        if (request) {
          await android.requestNotificationsPermission();
        }
        return await android.areNotificationsEnabled() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (ios == null) return false;
        if (request) {
          return await ios.requestPermissions(
                alert: true,
                badge: true,
                sound: true,
              ) ??
              false;
        }
        final options = await ios.checkPermissions();
        return options?.isEnabled ?? false;
      }
      if (Platform.isMacOS) {
        final mac = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        if (mac == null) return false;
        if (request) {
          return await mac.requestPermissions(
                alert: true,
                badge: true,
                sound: true,
              ) ??
              false;
        }
        final options = await mac.checkPermissions();
        return options?.isEnabled ?? false;
      }
      // Linux has no runtime permission model.
      return Platform.isLinux;
    } catch (e) {
      debugPrint('Notification permission check failed: $e');
      return false;
    }
  }

  /// Schedules (or re-schedules) the repeating daily reminder.
  ///
  /// Set [requestPermission] to false for silent re-scheduling at app start so
  /// the user isn't prompted on every launch.
  Future<ReminderScheduleResult> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool requestPermission = true,
  }) async {
    await initialize();
    if (!_initialized) return ReminderScheduleResult.failed;

    if (!await _hasPermission(request: requestPermission)) {
      return ReminderScheduleResult.permissionDenied;
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
      if (!scheduledDate.isAfter(now)) {
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
      return ReminderScheduleResult.scheduled;
    } catch (e) {
      debugPrint('Scheduling daily reminder failed: $e');
      return ReminderScheduleResult.failed;
    }
  }

  Future<void> cancelDailyReminder() async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.cancel(_dailyReminderId);
    } catch (e) {
      debugPrint('Cancelling daily reminder failed: $e');
    }
  }
}
