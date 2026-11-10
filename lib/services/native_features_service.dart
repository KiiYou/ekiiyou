import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/vocabulary_word.dart';

class NativeReviewEvent {
  final int wordId;
  final bool remembered;

  const NativeReviewEvent({required this.wordId, required this.remembered});
}

class NativeLaunchAction {
  final String action; // 'quick_add' | 'start_review' | 'open_word'
  final int? wordId;

  const NativeLaunchAction({required this.action, this.wordId});
}

class NativeFeaturesService {
  static final NativeFeaturesService instance = NativeFeaturesService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.ekiiyou/native_features',
  );

  VoidCallback? onNativeReviewRecorded;
  ValueChanged<NativeLaunchAction>? onLaunchAction;

  NativeFeaturesService._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onNativeReviewRecorded':
        onNativeReviewRecorded?.call();
        break;
      case 'onLaunchAction':
        final args = call.arguments;
        if (args is Map) {
          final action = args['action']?.toString();
          final rawWordId = args['wordId'];
          final wordId = rawWordId is int
              ? rawWordId
              : int.tryParse(rawWordId?.toString() ?? '');
          if (action != null && action.isNotEmpty) {
            onLaunchAction?.call(
              NativeLaunchAction(action: action, wordId: wordId),
            );
          }
        }
        break;
    }
  }

  Future<void> syncState({
    required List<VocabularyWord> wordsQueue,
    required int reviewedToday,
    required int dailyTarget,
    required int totalWords,
    required String languageCode,
    required bool floatingEnabled,
    required int floatingIntervalMinutes,
  }) async {
    if (!isSupported) return;
    try {
      final serializedWords = wordsQueue
          .take(40)
          .map(
            (w) => {
              'id': w.id ?? -1,
              'word': w.word,
              'arabicMeaning': w.arabicMeaning ?? '',
              'englishDefinition': w.englishDefinition ?? '',
              'phonetic': w.phonetic ?? '',
              'exampleSentence': w.exampleSentence ?? '',
              'audioLocalPath': w.audioLocalPath ?? '',
            },
          )
          .toList();

      await _channel.invokeMethod('syncState', {
        'wordsJson': jsonEncode(serializedWords),
        'reviewedToday': reviewedToday,
        'dailyTarget': dailyTarget,
        'totalWords': totalWords,
        'languageCode': languageCode,
        'floatingEnabled': floatingEnabled,
        'floatingIntervalMinutes': floatingIntervalMinutes,
      });
    } catch (_) {}
  }

  Future<List<NativeReviewEvent>> drainPendingReviews() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('drainPendingReviews');
      if (raw == null || raw.isEmpty || raw == '[]') return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final events = <NativeReviewEvent>[];
      for (final item in decoded) {
        if (item is Map) {
          final id = item['wordId'] is int
              ? item['wordId'] as int
              : int.tryParse(item['wordId']?.toString() ?? '');
          final remembered = item['remembered'] == true;
          if (id != null && id > 0) {
            events.add(NativeReviewEvent(wordId: id, remembered: remembered));
          }
        }
      }
      return events;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('checkOverlayPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestOverlayPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showFloatingPopupNow() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('showFloatingPopupNow') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPinWidget(String widgetType) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget', {
            'widgetType': widgetType,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<NativeLaunchAction?> consumeLaunchAction() async {
    if (!isSupported) return null;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumeLaunchAction',
      );
      if (raw == null) return null;
      final action = raw['action']?.toString();
      if (action == null || action.isEmpty) return null;
      final rawWordId = raw['wordId'];
      final wordId = rawWordId is int
          ? rawWordId
          : int.tryParse(rawWordId?.toString() ?? '');
      return NativeLaunchAction(action: action, wordId: wordId);
    } catch (_) {
      return null;
    }
  }
}
