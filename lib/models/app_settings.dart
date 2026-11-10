import 'package:flutter/material.dart';

enum SortOrder { newest, oldest, alphabetical }

class AppSettings {
  final int dailyReviewTarget;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final String languageCode; // 'ar' or 'en'
  final ThemeMode themeMode;

  const AppSettings({
    this.dailyReviewTarget = 10,
    this.reminderEnabled = false,
    this.reminderHour = 20, // Default 8:00 PM
    this.reminderMinute = 0,
    this.languageCode = 'ar', // Default Arabic RTL with English switching
    this.themeMode = ThemeMode.system,
  });

  TimeOfDay get reminderTime =>
      TimeOfDay(hour: reminderHour, minute: reminderMinute);

  bool get isArabic => languageCode == 'ar';

  AppSettings copyWith({
    int? dailyReviewTarget,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    String? languageCode,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      dailyReviewTarget: dailyReviewTarget ?? this.dailyReviewTarget,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      languageCode: languageCode ?? this.languageCode,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
