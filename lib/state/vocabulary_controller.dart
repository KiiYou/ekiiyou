import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/app_settings.dart';
import '../models/vocabulary_word.dart';
import '../services/audio_service.dart';
import '../services/dictionary_service.dart';
import '../services/notification_service.dart';
import '../services/spaced_repetition_service.dart';

class VocabularyController extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final DictionaryService _dictionaryService;
  final SpacedRepetitionService _spacedRepetition;
  final AudioPronunciationService _audioService;
  final NotificationService _notificationService;
  final bool enableConnectivityListener;

  List<VocabularyWord> _allWords = [];
  List<VocabularyWord> _filteredWords = [];
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.newest;

  AppSettings _settings = const AppSettings();
  Set<int> _reviewedTodayIds = {};
  String _currentDayKey = '';

  bool _isInitialized = false;
  bool _isAddingWord = false;
  bool _isSyncingPending = false;
  bool _isOffline = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  VocabularyController({
    DatabaseHelper? dbHelper,
    DictionaryService? dictionaryService,
    SpacedRepetitionService? spacedRepetition,
    AudioPronunciationService? audioService,
    NotificationService? notificationService,
    this.enableConnectivityListener = true,
  }) : _dbHelper = dbHelper ?? DatabaseHelper.instance,
       _dictionaryService = dictionaryService ?? StandardDictionaryService(),
       _spacedRepetition = spacedRepetition ?? const SpacedRepetitionService(),
       _audioService = audioService ?? AudioPronunciationService(),
       _notificationService =
           notificationService ?? NotificationService.instance;

  // Getters
  List<VocabularyWord> get allWords => List.unmodifiable(_allWords);
  List<VocabularyWord> get filteredWords => List.unmodifiable(_filteredWords);
  List<VocabularyWord> get recentWords => _allWords.take(5).toList();
  String get searchQuery => _searchQuery;
  SortOrder get sortOrder => _sortOrder;
  AppSettings get settings => _settings;
  AppStrings get strings => AppStrings(_settings.languageCode);

  bool get isInitialized => _isInitialized;
  bool get isAddingWord => _isAddingWord;
  bool get isSyncingPending => _isSyncingPending;
  bool get isOffline => _isOffline;

  int get totalWordsCount => _allWords.length;
  int get pendingWordsCount => _allWords
      .where((w) => w.informationStatus == InformationStatus.pending)
      .length;
  int get dueWordsCount => _spacedRepetition.countDueWords(_allWords);

  int get reviewedTodayCount {
    _ensureCurrentDayKey();
    return _reviewedTodayIds.length;
  }

  Set<int> get reviewedTodayIds {
    _ensureCurrentDayKey();
    return Set.unmodifiable(_reviewedTodayIds);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadSettingsAndDailyProgress();
    await refreshWords();
    _isInitialized = true;
    notifyListeners();

    if (enableConnectivityListener) {
      _setupConnectivityMonitoring();
    }
  }

  Future<void> _loadSettingsAndDailyProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final dailyTarget = prefs.getInt('daily_review_target') ?? 10;
    final reminderEnabled = prefs.getBool('reminder_enabled') ?? false;
    final reminderHour = prefs.getInt('reminder_hour') ?? 20;
    final reminderMinute = prefs.getInt('reminder_minute') ?? 0;
    final languageCode = prefs.getString('language_code') ?? 'ar';
    final themeIndex = prefs.getInt('theme_mode') ?? ThemeMode.system.index;

    _settings = AppSettings(
      dailyReviewTarget: dailyTarget.clamp(1, 200),
      reminderEnabled: reminderEnabled,
      reminderHour: reminderHour.clamp(0, 23),
      reminderMinute: reminderMinute.clamp(0, 59),
      languageCode: (languageCode == 'en' || languageCode == 'ar')
          ? languageCode
          : 'ar',
      themeMode:
          ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)],
    );

    _currentDayKey = _todayKey();
    final savedDayKey = prefs.getString('reviewed_day_key') ?? '';
    if (savedDayKey == _currentDayKey) {
      final list = prefs.getStringList('reviewed_today_ids') ?? [];
      _reviewedTodayIds = list
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toSet();
    } else {
      _reviewedTodayIds = {};
      await prefs.setString('reviewed_day_key', _currentDayKey);
      await prefs.setStringList('reviewed_today_ids', []);
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _ensureCurrentDayKey() {
    final today = _todayKey();
    if (_currentDayKey != today) {
      _currentDayKey = today;
      _reviewedTodayIds = {};
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('reviewed_day_key', _currentDayKey);
        prefs.setStringList('reviewed_today_ids', []);
      });
    }
  }

  void _setupConnectivityMonitoring() {
    try {
      final connectivity = Connectivity();
      connectivity.checkConnectivity().then((results) {
        final offline = results.contains(ConnectivityResult.none);
        _isOffline = offline;
        notifyListeners();
        if (!offline) {
          syncPendingWords();
        }
      });

      _connectivitySubscription = connectivity.onConnectivityChanged.listen((
        results,
      ) {
        final offline = results.contains(ConnectivityResult.none);
        final wasOffline = _isOffline;
        _isOffline = offline;
        notifyListeners();
        if (!offline && (wasOffline || pendingWordsCount > 0)) {
          syncPendingWords();
        }
      });
    } catch (_) {}
  }

  Future<void> refreshWords() async {
    _allWords = await _dbHelper.getAllWords(sortOrder: SortOrder.newest);
    await _applySearchAndSort();
    notifyListeners();
  }

  Future<void> _applySearchAndSort() async {
    if (_searchQuery.trim().isEmpty && _sortOrder == SortOrder.newest) {
      _filteredWords = List.from(_allWords);
    } else {
      _filteredWords = await _dbHelper.getAllWords(
        searchQuery: _searchQuery,
        sortOrder: _sortOrder,
      );
    }
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    await _applySearchAndSort();
    notifyListeners();
  }

  Future<void> setSortOrder(SortOrder order) async {
    if (_sortOrder == order) return;
    _sortOrder = order;
    await _applySearchAndSort();
    notifyListeners();
  }

  /// Checks if a word already exists (ignoring case & extra spaces).
  Future<VocabularyWord?> findExistingDuplicate(
    String rawWord, {
    int? ignoreId,
  }) async {
    final existing = await _dbHelper.getWordByNormalized(rawWord);
    if (existing != null && existing.id != ignoreId) {
      return existing;
    }
    return null;
  }

  /// Adds a new English word, automatically retrieving dictionary info when online,
  /// or saving immediately as `pending` when offline.
  Future<VocabularyWord> addWord({
    required String rawWord,
    String? manualArabicMeaning,
    String? manualEnglishDefinition,
    String? manualPartOfSpeech,
    String? manualPhonetic,
    String? manualExampleSentence,
    String? manualExampleTranslation,
  }) async {
    final cleaned = rawWord.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = VocabularyWord.normalize(cleaned);
    if (normalized.isEmpty) {
      throw ArgumentError('Word cannot be empty');
    }

    final existing = await _dbHelper.getWordByNormalized(normalized);
    if (existing != null) {
      throw DuplicateWordException(existing);
    }

    _isAddingWord = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      DictionaryLookupResult? lookup;

      if (!_isOffline) {
        lookup = await _dictionaryService.lookupWord(cleaned);
      }

      String? trimOrNull(String? value) {
        if (value == null) return null;
        final t = value.trim();
        return t.isEmpty ? null : t;
      }

      final arabicMeaning =
          trimOrNull(manualArabicMeaning) ?? lookup?.arabicMeaning;
      final englishDefinition =
          trimOrNull(manualEnglishDefinition) ?? lookup?.englishDefinition;
      final partOfSpeech =
          trimOrNull(manualPartOfSpeech) ?? lookup?.partOfSpeech;
      final phonetic = trimOrNull(manualPhonetic) ?? lookup?.phonetic;
      final exampleSentence =
          trimOrNull(manualExampleSentence) ?? lookup?.exampleSentence;
      final exampleTranslation =
          trimOrNull(manualExampleTranslation) ?? lookup?.exampleTranslation;

      final InformationStatus status;
      if (arabicMeaning != null || englishDefinition != null) {
        status = InformationStatus.complete;
      } else if (lookup == null) {
        status = InformationStatus.pending;
      } else {
        status = lookup.status;
      }

      final newWord = VocabularyWord(
        word: cleaned,
        normalizedWord: normalized,
        arabicMeaning: arabicMeaning,
        englishDefinition: englishDefinition,
        partOfSpeech: partOfSpeech,
        phonetic: phonetic,
        audioLocalPath: lookup?.audioLocalPath,
        audioRemoteUrl: lookup?.audioRemoteUrl,
        exampleSentence: exampleSentence,
        exampleTranslation: exampleTranslation,
        createdAt: now,
        updatedAt: now,
        nextReviewAt: now, // Immediately eligible for daily review
        informationStatus: status,
      );

      final saved = await _dbHelper.insertWord(newWord);
      await refreshWords();
      return saved;
    } finally {
      _isAddingWord = false;
      notifyListeners();
    }
  }

  Future<VocabularyWord> updateWord(VocabularyWord updatedWord) async {
    final hasCoreInfo =
        (updatedWord.arabicMeaning != null &&
            updatedWord.arabicMeaning!.trim().isNotEmpty) ||
        (updatedWord.englishDefinition != null &&
            updatedWord.englishDefinition!.trim().isNotEmpty);

    final effectiveStatus = hasCoreInfo
        ? InformationStatus.complete
        : updatedWord.informationStatus;

    final saved = await _dbHelper.updateWord(
      updatedWord.copyWith(informationStatus: effectiveStatus),
    );
    await refreshWords();
    return saved;
  }

  Future<void> deleteWord(int id) async {
    await _dbHelper.deleteWord(id);
    _reviewedTodayIds.remove(id);
    await _persistReviewedToday();
    await refreshWords();
  }

  /// Retries dictionary lookup for a single word and updates it in SQLite.
  Future<VocabularyWord> retryDictionaryLookup(VocabularyWord word) async {
    if (word.id == null) return word;
    final lookup = await _dictionaryService.lookupWord(word.word);

    final updated = word.copyWith(
      arabicMeaning: word.arabicMeaning ?? lookup.arabicMeaning,
      englishDefinition: word.englishDefinition ?? lookup.englishDefinition,
      partOfSpeech: word.partOfSpeech ?? lookup.partOfSpeech,
      phonetic: word.phonetic ?? lookup.phonetic,
      audioLocalPath: word.audioLocalPath ?? lookup.audioLocalPath,
      audioRemoteUrl: word.audioRemoteUrl ?? lookup.audioRemoteUrl,
      exampleSentence: word.exampleSentence ?? lookup.exampleSentence,
      exampleTranslation: word.exampleTranslation ?? lookup.exampleTranslation,
      informationStatus:
          (word.arabicMeaning != null ||
              lookup.arabicMeaning != null ||
              word.englishDefinition != null ||
              lookup.englishDefinition != null)
          ? InformationStatus.complete
          : lookup.status,
      updatedAt: DateTime.now(),
    );

    final saved = await _dbHelper.updateWord(updated);
    await refreshWords();
    return saved;
  }

  /// Automatically attempts to retrieve missing information for all `pending` words.
  Future<int> syncPendingWords() async {
    if (_isSyncingPending) return 0;
    final pendingList = await _dbHelper.getPendingWords();
    if (pendingList.isEmpty) return 0;

    _isSyncingPending = true;
    notifyListeners();

    int updatedCount = 0;
    try {
      for (final word in pendingList) {
        final lookup = await _dictionaryService.lookupWord(word.word);
        if (lookup.status == InformationStatus.pending && !lookup.hasAnyData) {
          // Still offline or network error; stop batch early
          break;
        }
        final updated = word.copyWith(
          arabicMeaning: word.arabicMeaning ?? lookup.arabicMeaning,
          englishDefinition: word.englishDefinition ?? lookup.englishDefinition,
          partOfSpeech: word.partOfSpeech ?? lookup.partOfSpeech,
          phonetic: word.phonetic ?? lookup.phonetic,
          audioLocalPath: word.audioLocalPath ?? lookup.audioLocalPath,
          audioRemoteUrl: word.audioRemoteUrl ?? lookup.audioRemoteUrl,
          exampleSentence: word.exampleSentence ?? lookup.exampleSentence,
          exampleTranslation:
              word.exampleTranslation ?? lookup.exampleTranslation,
          informationStatus: lookup.status,
          updatedAt: DateTime.now(),
        );
        await _dbHelper.updateWord(updated);
        if (lookup.status == InformationStatus.complete) {
          updatedCount++;
        }
      }
      await refreshWords();
      return updatedCount;
    } finally {
      _isSyncingPending = false;
      notifyListeners();
    }
  }

  /// Plays pronunciation audio (cached local file -> remote URL -> offline TTS fallback).
  Future<bool> playPronunciation(VocabularyWord word) async {
    // Also lazily cache the remote audio in the background if not yet cached locally
    if ((word.audioLocalPath == null || word.audioLocalPath!.isEmpty) &&
        word.audioRemoteUrl != null &&
        word.audioRemoteUrl!.isNotEmpty &&
        !_isOffline &&
        word.id != null) {
      _dictionaryService
          .cacheAudioFile(word.normalizedWord, word.audioRemoteUrl!)
          .then((cachedPath) async {
            if (cachedPath != null) {
              await _dbHelper.updateWord(
                word.copyWith(audioLocalPath: cachedPath),
              );
              await refreshWords();
            }
          });
    }
    return _audioService.playWordPronunciation(word);
  }

  /// Builds a non-repeating list of flashcards for the current review session.
  List<VocabularyWord> buildReviewSessionQueue() {
    _ensureCurrentDayKey();
    final remainingForTarget =
        (_settings.dailyReviewTarget - _reviewedTodayIds.length).clamp(
          0,
          _settings.dailyReviewTarget,
        );
    // If the user has already reached today's target and taps "Review More Words",
    // provide a fresh batch up to dailyReviewTarget.
    final sessionLimit = remainingForTarget > 0
        ? remainingForTarget
        : _settings.dailyReviewTarget;

    return _spacedRepetition.selectWordsForSession(
      allWords: _allWords,
      sessionLimit: sessionLimit,
      reviewedTodayIds: remainingForTarget > 0 ? _reviewedTodayIds : const {},
    );
  }

  /// Records a flashcard review result (Remembered or Forgot) and persists daily progress.
  Future<VocabularyWord> recordWordReview({
    required VocabularyWord word,
    required bool remembered,
  }) async {
    _ensureCurrentDayKey();
    final updated = _spacedRepetition.recordReview(
      word: word,
      remembered: remembered,
    );
    final saved = await _dbHelper.updateWord(updated);

    if (saved.id != null) {
      _reviewedTodayIds.add(saved.id!);
      await _persistReviewedToday();
    }
    await refreshWords();
    return saved;
  }

  Future<void> _persistReviewedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reviewed_day_key', _currentDayKey);
    await prefs.setStringList(
      'reviewed_today_ids',
      _reviewedTodayIds.map((e) => e.toString()).toList(),
    );
  }

  // Settings actions
  Future<void> updateDailyTarget(int target) async {
    final clamped = target.clamp(1, 200);
    _settings = _settings.copyWith(dailyReviewTarget: clamped);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_review_target', clamped);
  }

  Future<bool> setReminderEnabled(bool enabled) async {
    if (enabled) {
      final scheduled = await _notificationService.scheduleDailyReminder(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
        title: strings.notificationTitle,
        body: strings.notificationBody,
      );
      if (!scheduled) {
        return false;
      }
    } else {
      await _notificationService.cancelDailyReminder();
    }

    _settings = _settings.copyWith(reminderEnabled: enabled);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_enabled', enabled);
    return true;
  }

  Future<void> updateReminderTime(TimeOfDay time) async {
    _settings = _settings.copyWith(
      reminderHour: time.hour,
      reminderMinute: time.minute,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_hour', time.hour);
    await prefs.setInt('reminder_minute', time.minute);

    if (_settings.reminderEnabled) {
      await _notificationService.scheduleDailyReminder(
        hour: time.hour,
        minute: time.minute,
        title: strings.notificationTitle,
        body: strings.notificationBody,
      );
    }
  }

  Future<void> updateLanguage(String languageCode) async {
    if (languageCode != 'ar' && languageCode != 'en') return;
    _settings = _settings.copyWith(languageCode: languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', languageCode);

    if (_settings.reminderEnabled) {
      await _notificationService.scheduleDailyReminder(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
        title: strings.notificationTitle,
        body: strings.notificationBody,
      );
    }
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<String> exportBackupJson() async {
    return _dbHelper.exportAllWordsJson();
  }

  Future<int> importBackupJson(String jsonString) async {
    final count = await _dbHelper.importWordsJson(jsonString);
    await refreshWords();
    return count;
  }

  Future<void> clearAllData() async {
    await _dbHelper.clearAllWords();
    _reviewedTodayIds.clear();
    await _persistReviewedToday();
    await refreshWords();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _audioService.dispose();
    super.dispose();
  }
}
