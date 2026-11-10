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
import '../services/native_features_service.dart';
import '../services/notification_service.dart';
import '../services/spaced_repetition_service.dart';

class ReviewSession {
  final List<VocabularyWord> words;

  /// True when the user asked for extra practice with words that aren't due.
  final bool isPractice;

  const ReviewSession({required this.words, required this.isPractice});
}

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
  bool _pendingFloatingEnableAfterPermission = false;
  bool _pendingShowPopupAfterPermission = false;
  final Set<int> _enrichingIds = {};
  final Set<Future<void>> _enrichmentTasks = {};

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
  bool get isSyncingPending => _isSyncingPending || _enrichingIds.isNotEmpty;
  bool get isOffline => _isOffline;
  bool isEnriching(int? wordId) =>
      wordId != null && _enrichingIds.contains(wordId);

  int get totalWordsCount => _allWords.length;
  int get pendingWordsCount => _allWords
      .where((w) => w.informationStatus == InformationStatus.pending)
      .length;
  int get dueWordsCount => _spacedRepetition.countDueWords(_allWords);

  int get reviewedTodayCount => _reviewedTodayIds.length;

  Set<int> get reviewedTodayIds => Set.unmodifiable(_reviewedTodayIds);

  /// Resets the daily counter if the calendar day has rolled over (e.g. when
  /// the app resumes after midnight) and syncs any reviews made from Android
  /// Home Screen widgets or the floating popup bubble.
  void checkDayRollover() {
    if (_ensureCurrentDayKey()) {
      notifyListeners();
      _syncNativeState();
    }
    if (enableConnectivityListener) {
      drainAndApplyNativeReviews();
      _checkPendingOverlayPermissionOnResume();
    }
  }

  Future<void> _checkPendingOverlayPermissionOnResume() async {
    if (!_pendingFloatingEnableAfterPermission &&
        !_pendingShowPopupAfterPermission) {
      return;
    }
    final hasPerm = await NativeFeaturesService.instance
        .checkOverlayPermission();
    if (!hasPerm) return;

    final shouldEnable = _pendingFloatingEnableAfterPermission;
    final shouldShow = _pendingShowPopupAfterPermission;
    _pendingFloatingEnableAfterPermission = false;
    _pendingShowPopupAfterPermission = false;

    if (shouldEnable) {
      await setFloatingBubbleEnabled(true);
    } else if (shouldShow) {
      await showFloatingPopupNow();
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadSettingsAndDailyProgress();
    await refreshWords();
    _isInitialized = true;
    notifyListeners();

    if (enableConnectivityListener) {
      NativeFeaturesService.instance.onNativeReviewRecorded = () {
        drainAndApplyNativeReviews();
      };
      await drainAndApplyNativeReviews();
      _audioService.warmup();
      _setupConnectivityMonitoring();
      _precacheMissingAudioFiles();
      if (_settings.reminderEnabled) {
        _reverifyReminderAtStartup();
      }
    }
  }

  /// Drains any word reviews recorded natively from the Home Screen widgets
  /// or the floating word popup and applies them to SQLite & today's counter.
  Future<void> drainAndApplyNativeReviews() async {
    final events = await NativeFeaturesService.instance.drainPendingReviews();
    if (events.isEmpty) return;

    _ensureCurrentDayKey();
    for (final event in events) {
      final existing = await _dbHelper.getWordById(event.wordId);
      if (existing != null) {
        final updated = _spacedRepetition.recordReview(
          word: existing,
          remembered: event.remembered,
          isPractice: false,
        );
        await _dbHelper.updateWord(updated);
        _reviewedTodayIds.add(event.wordId);
      }
    }
    await _persistReviewedToday();
    await refreshWords();
  }

  void _syncNativeState() {
    if (!enableConnectivityListener) return;
    final dueWords = _spacedRepetition.selectDueWords(
      allWords: _allWords,
      limit: 30,
    );
    final dueIds = dueWords.map((w) => w.id).toSet();
    final extraPractice = _spacedRepetition
        .selectPracticeWords(allWords: _allWords, limit: 30)
        .where((w) => !dueIds.contains(w.id));
    final queue = <VocabularyWord>[...dueWords, ...extraPractice];

    NativeFeaturesService.instance.syncState(
      wordsQueue: queue,
      reviewedToday: _reviewedTodayIds.length,
      dailyTarget: _settings.dailyReviewTarget,
      totalWords: _allWords.length,
      languageCode: _settings.languageCode,
      floatingEnabled: _settings.floatingBubbleEnabled,
      floatingIntervalMinutes: _settings.floatingIntervalMinutes,
    );
  }

  /// Silently downloads and caches local MP3 files for any previously saved
  /// words that don't have a cached audio file yet.
  Future<void> _precacheMissingAudioFiles() async {
    if (_isOffline) return;
    final missingAudio = _allWords
        .where(
          (w) =>
              w.id != null &&
              (w.audioLocalPath == null || w.audioLocalPath!.trim().isEmpty),
        )
        .toList();
    if (missingAudio.isEmpty) return;

    bool changed = false;
    for (final w in missingAudio) {
      if (_isOffline) break;
      final cachedPath = await _dictionaryService.cacheAudioFile(
        w.normalizedWord,
        w.audioRemoteUrl,
      );
      if (cachedPath != null) {
        final latest = await _dbHelper.getWordById(w.id!);
        if (latest != null) {
          await _dbHelper.updateWord(
            latest.copyWith(audioLocalPath: cachedPath),
          );
          changed = true;
        }
      }
    }
    if (changed) {
      await refreshWords();
    }
  }

  /// Re-schedules the alarm so OS clears / app updates don't lose it, and turns
  /// the toggle off if the user revoked notification permission in settings.
  Future<void> _reverifyReminderAtStartup() async {
    final result = await _notificationService.scheduleDailyReminder(
      hour: _settings.reminderHour,
      minute: _settings.reminderMinute,
      title: strings.notificationTitle,
      body: strings.notificationBody,
      requestPermission: false,
    );
    if (result != ReminderScheduleResult.scheduled) {
      _settings = _settings.copyWith(reminderEnabled: false);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reminder_enabled', false);
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
    final floatingBubbleEnabled =
        prefs.getBool('floating_bubble_enabled') ?? false;
    final floatingIntervalMinutes =
        prefs.getInt('floating_interval_minutes') ?? 60;

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
      floatingBubbleEnabled: floatingBubbleEnabled,
      floatingIntervalMinutes: floatingIntervalMinutes.clamp(15, 720),
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

  bool _ensureCurrentDayKey() {
    final today = _todayKey();
    if (_currentDayKey.isNotEmpty && _currentDayKey != today) {
      _currentDayKey = today;
      _reviewedTodayIds = {};
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('reviewed_day_key', _currentDayKey);
        prefs.setStringList('reviewed_today_ids', []);
      });
      return true;
    }
    return false;
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
    _applySearchAndSort();
    notifyListeners();
    _syncNativeState();
  }

  void _applySearchAndSort() {
    final trimmed = _searchQuery.trim();
    Iterable<VocabularyWord> matches = _allWords;

    if (trimmed.isNotEmpty) {
      final normQuery = VocabularyWord.normalize(trimmed);
      final normArQuery = VocabularyWord.normalizeArabic(trimmed);
      matches = _allWords.where((w) {
        if (w.normalizedWord.contains(normQuery) ||
            w.word.toLowerCase().contains(normQuery)) {
          return true;
        }
        final meaning = w.arabicMeaning;
        if (meaning != null && meaning.isNotEmpty) {
          if (meaning.contains(trimmed) ||
              VocabularyWord.normalizeArabic(meaning).contains(normArQuery)) {
            return true;
          }
        }
        return false;
      });
    }

    final list = matches.toList();
    switch (_sortOrder) {
      case SortOrder.newest:
        // _allWords is already ordered newest-first from SQLite
        break;
      case SortOrder.oldest:
        list.sort((a, b) {
          final cmp = a.createdAt.compareTo(b.createdAt);
          return cmp != 0 ? cmp : (a.id ?? 0).compareTo(b.id ?? 0);
        });
        break;
      case SortOrder.alphabetical:
        list.sort((a, b) => a.normalizedWord.compareTo(b.normalizedWord));
        break;
    }
    _filteredWords = list;
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    _applySearchAndSort();
    notifyListeners();
  }

  Future<void> setSortOrder(SortOrder order) async {
    if (_sortOrder == order) return;
    _sortOrder = order;
    _applySearchAndSort();
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

  /// Saves a new English word immediately, then fetches its dictionary
  /// information in the background so the user never waits on the network.
  ///
  /// The returned word has `pending` status (unless the user typed the meaning
  /// and definition manually). Use [isEnriching] to show a loading state.
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
      String? trimOrNull(String? value) {
        if (value == null) return null;
        final t = value.trim();
        return t.isEmpty ? null : t;
      }

      final now = DateTime.now();
      final arabicMeaning = trimOrNull(manualArabicMeaning);
      final englishDefinition = trimOrNull(manualEnglishDefinition);

      final newWord = VocabularyWord(
        word: cleaned,
        normalizedWord: normalized,
        arabicMeaning: arabicMeaning,
        englishDefinition: englishDefinition,
        partOfSpeech: trimOrNull(manualPartOfSpeech),
        phonetic: trimOrNull(manualPhonetic),
        exampleSentence: trimOrNull(manualExampleSentence),
        exampleTranslation: trimOrNull(manualExampleTranslation),
        createdAt: now,
        updatedAt: now,
        nextReviewAt: now, // Immediately eligible for daily review
        informationStatus: InformationStatus.pending,
      );

      final saved = await _dbHelper.insertWord(newWord);
      await refreshWords();

      if (!_isOffline && saved.id != null) {
        _startBackgroundEnrichment(saved.id!);
      }
      return saved;
    } finally {
      _isAddingWord = false;
      notifyListeners();
    }
  }

  void _startBackgroundEnrichment(int id) {
    if (_enrichingIds.contains(id)) return;
    _enrichingIds.add(id);
    notifyListeners();

    late final Future<void> task;
    task = _enrichWord(id).whenComplete(() {
      _enrichingIds.remove(id);
      _enrichmentTasks.remove(task);
      notifyListeners();
    });
    _enrichmentTasks.add(task);
  }

  /// Looks the word up and merges the result into the *latest* stored copy,
  /// so edits or reviews made while the request was in flight aren't lost.
  Future<VocabularyWord?> _enrichWord(int id) async {
    final before = await _dbHelper.getWordById(id);
    if (before == null) return null;

    final lookup = await _dictionaryService.lookupWord(before.word);

    final latest = await _dbHelper.getWordById(id);
    if (latest == null) return null; // deleted meanwhile

    final merged = _mergeLookup(latest, lookup);
    final saved = await _dbHelper.updateWord(merged);
    await refreshWords();
    return saved;
  }

  /// Fills only the fields the user hasn't set, and derives the status.
  VocabularyWord _mergeLookup(
    VocabularyWord word,
    DictionaryLookupResult lookup,
  ) {
    final merged = word.copyWith(
      arabicMeaning: word.arabicMeaning ?? lookup.arabicMeaning,
      englishDefinition: word.englishDefinition ?? lookup.englishDefinition,
      partOfSpeech: word.partOfSpeech ?? lookup.partOfSpeech,
      phonetic: word.phonetic ?? lookup.phonetic,
      audioLocalPath: word.audioLocalPath ?? lookup.audioLocalPath,
      audioRemoteUrl: word.audioRemoteUrl ?? lookup.audioRemoteUrl,
      exampleSentence: word.exampleSentence ?? lookup.exampleSentence,
      exampleTranslation: word.exampleTranslation ?? lookup.exampleTranslation,
      updatedAt: DateTime.now(),
    );

    bool has(String? v) => v != null && v.trim().isNotEmpty;
    final hasMeaning = has(merged.arabicMeaning);
    final hasDefinition = has(merged.englishDefinition);

    final InformationStatus status;
    if (hasMeaning && hasDefinition) {
      status = InformationStatus.complete;
    } else if (lookup.status == InformationStatus.pending) {
      status = InformationStatus.pending; // network trouble: retry later
    } else if (hasMeaning || hasDefinition || lookup.hasAnyData) {
      status = InformationStatus.complete; // that's all the dictionary has
    } else {
      status = InformationStatus.unavailable;
    }
    return merged.copyWith(informationStatus: status);
  }

  /// Completes when all background lookups started so far have finished.
  @visibleForTesting
  Future<void> waitForBackgroundLookups() async {
    while (_enrichmentTasks.isNotEmpty) {
      await Future.wait(_enrichmentTasks.toList());
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
    final id = word.id;
    if (id == null || _enrichingIds.contains(id)) return word;
    _enrichingIds.add(id);
    notifyListeners();
    try {
      return await _enrichWord(id) ?? word;
    } finally {
      _enrichingIds.remove(id);
      notifyListeners();
    }
  }

  /// Automatically attempts to retrieve missing information for all `pending` words.
  /// Returns how many words became complete.
  Future<int> syncPendingWords() async {
    if (_isSyncingPending) return 0;
    final pendingList = (await _dbHelper.getPendingWords())
        .where((w) => w.id != null && !_enrichingIds.contains(w.id))
        .toList();
    if (pendingList.isEmpty) return 0;

    _isSyncingPending = true;
    notifyListeners();

    int completedCount = 0;
    try {
      for (final word in pendingList) {
        final id = word.id!;
        _enrichingIds.add(id);
        notifyListeners();
        VocabularyWord? saved;
        try {
          saved = await _enrichWord(id);
        } finally {
          _enrichingIds.remove(id);
        }
        if (saved == null) continue;
        if (saved.informationStatus == InformationStatus.complete) {
          completedCount++;
        } else if (saved.informationStatus == InformationStatus.pending) {
          // Still failing at the network level: stop instead of hammering.
          break;
        }
      }
      return completedCount;
    } finally {
      _isSyncingPending = false;
      notifyListeners();
    }
  }

  /// Plays pronunciation audio:
  /// - Uses local cached MP3 immediately if present on disk.
  /// - If no local MP3 exists yet and the device is online, quickly caches the
  ///   MP3 (from dictionary URL or fallback TTS MP3) and plays it.
  /// - Falls back to pre-warmed offline system TTS when offline.
  Future<bool> playPronunciation(VocabularyWord word) async {
    var targetWord = word;
    if ((targetWord.audioLocalPath == null ||
            targetWord.audioLocalPath!.trim().isEmpty) &&
        !_isOffline) {
      final cachedPath = await _dictionaryService.cacheAudioFile(
        targetWord.normalizedWord,
        targetWord.audioRemoteUrl,
      );
      if (cachedPath != null) {
        targetWord = targetWord.copyWith(audioLocalPath: cachedPath);
        if (targetWord.id != null) {
          final latest = await _dbHelper.getWordById(targetWord.id!);
          if (latest != null) {
            await _dbHelper.updateWord(
              latest.copyWith(audioLocalPath: cachedPath),
            );
            await refreshWords();
          }
        }
      }
    }
    return _audioService.playWordPronunciation(targetWord);
  }

  /// Builds the flashcards for a review session.
  ///
  /// Normally only words that are due are included. When nothing is due and
  /// the user explicitly asks to practice anyway, pass [practice] = true to get
  /// upcoming words in a practice session that won't inflate their intervals.
  ReviewSession buildReviewSession({bool practice = false}) {
    _ensureCurrentDayKey();
    final target = _settings.dailyReviewTarget;
    final remaining = target - _reviewedTodayIds.length;
    // Once today's target is met, "Review More Words" offers another batch.
    final limit = remaining > 0 ? remaining : target;

    if (practice) {
      return ReviewSession(
        words: _spacedRepetition.selectPracticeWords(
          allWords: _allWords,
          limit: limit,
        ),
        isPractice: true,
      );
    }
    return ReviewSession(
      words: _spacedRepetition.selectDueWords(
        allWords: _allWords,
        limit: limit,
      ),
      isPractice: false,
    );
  }

  /// Records a flashcard answer and persists daily progress.
  ///
  /// The answer is applied to the latest stored copy of the word, so a
  /// background dictionary lookup that finished mid-session isn't overwritten.
  Future<VocabularyWord> recordWordReview({
    required VocabularyWord word,
    required bool remembered,
    bool isPractice = false,
  }) async {
    _ensureCurrentDayKey();
    final latest = word.id != null
        ? (await _dbHelper.getWordById(word.id!) ?? word)
        : word;
    final updated = _spacedRepetition.recordReview(
      word: latest,
      remembered: remembered,
      isPractice: isPractice,
    );
    final saved = identical(updated, latest)
        ? latest
        : await _dbHelper.updateWord(updated);

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
    _syncNativeState();
  }

  Future<ReminderScheduleResult> setReminderEnabled(bool enabled) async {
    if (enabled) {
      final result = await _notificationService.scheduleDailyReminder(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
        title: strings.notificationTitle,
        body: strings.notificationBody,
      );
      if (result != ReminderScheduleResult.scheduled) {
        return result;
      }
    } else {
      await _notificationService.cancelDailyReminder();
    }

    _settings = _settings.copyWith(reminderEnabled: enabled);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_enabled', enabled);
    return ReminderScheduleResult.scheduled;
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
    _syncNativeState();

    if (_settings.reminderEnabled) {
      await _notificationService.scheduleDailyReminder(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
        title: strings.notificationTitle,
        body: strings.notificationBody,
      );
    }
  }

  /// Enables or disables the Messenger-style floating word bubble.
  /// Returns `false` if overlay permission is missing (and opens the system
  /// permission page so the user can grant it).
  Future<bool> setFloatingBubbleEnabled(bool enabled) async {
    if (enabled && NativeFeaturesService.instance.isSupported) {
      final hasPerm = await NativeFeaturesService.instance
          .checkOverlayPermission();
      if (!hasPerm) {
        _pendingFloatingEnableAfterPermission = true;
        await NativeFeaturesService.instance.requestOverlayPermission();
        return false;
      }
    }
    _pendingFloatingEnableAfterPermission = false;

    _settings = _settings.copyWith(floatingBubbleEnabled: enabled);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('floating_bubble_enabled', enabled);
    _syncNativeState();
    if (enabled) {
      await NativeFeaturesService.instance.showFloatingPopupNow();
    }
    return true;
  }

  Future<void> updateFloatingIntervalMinutes(int minutes) async {
    final clamped = minutes.clamp(15, 720);
    _settings = _settings.copyWith(floatingIntervalMinutes: clamped);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('floating_interval_minutes', clamped);
    _syncNativeState();
  }

  /// Immediately displays the Messenger-style floating word popup on screen.
  /// Returns `false` if overlay permission is required.
  Future<bool> showFloatingPopupNow() async {
    if (!NativeFeaturesService.instance.isSupported) return false;
    final hasPerm = await NativeFeaturesService.instance
        .checkOverlayPermission();
    if (!hasPerm) {
      _pendingShowPopupAfterPermission = true;
      await NativeFeaturesService.instance.requestOverlayPermission();
      return false;
    }
    _pendingShowPopupAfterPermission = false;
    _syncNativeState();
    return NativeFeaturesService.instance.showFloatingPopupNow();
  }

  Future<bool> requestPinHomeWidget(String widgetType) async {
    _syncNativeState();
    return NativeFeaturesService.instance.requestPinWidget(widgetType);
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
